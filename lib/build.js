const path = require('path');
const util = require('util');
const crypto = require('crypto');
const chalk = require('chalk');
const fs = require('fs-extra');
const wrap = require('wrap-ansi');
const {hashElement} = require('folder-hash');
const elmCompiler = require('../vendor/node-elm-compiler');
const {getElmBinary} = require('./elm-binary');
const templateDependencies = require('./template-dependencies');
const errorMessage = require('./error-message');
const debug = require('./debug');

const fsEnsureDir = util.promisify(fs.ensureDir);
const fsReadJson = util.promisify(fs.readJson);

async function cachedBuild(options, userSrc, reviewElmJsonPath, reviewElmJson) {
  const hashes = await Promise.all(
    reviewElmJson['source-directories']
      .map((directory) =>
        hashElement(path.resolve(userSrc, directory), {
          folders: {exclude: ['.*', 'node_modules', 'elm-stuff']},
          files: {include: ['*.elm']},
          algo: 'md5'
        })
      )
      .concat(hashElement(reviewElmJsonPath, {algo: 'md5'}))
  );

  const hash = hashes
    .reduce(
      (resultHash, {hash}) => resultHash.update(hash),
      crypto.createHash('md5')
    )
    .digest('hex');

  return `${hash}${options.localElmReviewSrc ? '-local' : ''}${
    options.debug ? '-debug' : ''
  }`;
}

async function build(options) {
  const projectToReview = options.projectToReview();
  const userSrc = options.userSrc();
  const reviewElmJsonPath = path.join(userSrc, 'elm.json');

  const reviewElmJson = await fsReadJson(reviewElmJsonPath).catch((error) => {
    if (error.code === 'ENOENT') {
      return Promise.reject(
        new errorMessage.CustomError(
          /* eslint-disable prettier/prettier */
'INCORRECT CONFIGURATION',
`I could not find a review configuration. I was expecting to find an ${chalk.yellowBright('elm.json')} file and a ${chalk.cyan('ReviewConfig.elm')} file in ${chalk.cyan(path.dirname(reviewElmJsonPath))}${chalk.cyan('/')}.

I can help set you up with an initial configuration if you run ${chalk.cyanBright('elm-review init')}.`,
options.elmJsonPath
          /* eslint-enable prettier/prettier */
        )
      );
    }

    return Promise.reject(error);
  });

  validateElmReviewVersion(
    options,
    reviewElmJsonPath,
    reviewElmJson.dependencies.direct['jfmengels/elm-review']
  );

  const appHash = await cachedBuild(
    options,
    userSrc,
    reviewElmJsonPath,
    reviewElmJson
  );

  const pathToAppDirectory = options.pathToApplicationDirectory(appHash);
  const elmModulePath = path.resolve(pathToAppDirectory, 'main.js');
  if (fs.existsSync(elmModulePath)) {
    debug(`Review application is already built. Using ${elmModulePath}`);
  } else {
    debug('Starting review application build');

    await Promise.all([
      getElmBinary(options),
      createTemplateProject(
        options,
        pathToAppDirectory,
        projectToReview,
        reviewElmJson
      )
    ]).then(([elmBinary]) => {
      debug('Compiling review application');

      return compileElmProject(
        options,
        pathToAppDirectory,
        elmModulePath,
        elmBinary
      );
    });

    debug('Finished review application build');
  }

  return {
    elmModulePath,
    reviewElmJsonPath,
    reviewElmJson
  };
}

async function createTemplateProject(
  options,
  dest,
  projectToReview,
  reviewElmJson
) {
  // Source directories
  const templateSrc = path.join(__dirname, '../template/src');
  const userSrc = options.userSrc();
  const reviewElmJsonPath = path.join(userSrc, 'elm.json');

  // Destination directories
  const projectFolder = path.join(dest, 'project');
  const elmJsonPath = path.join(projectFolder, 'elm.json');
  const elmReviewSrc = path.join(projectFolder, 'elm-review-src');

  // Promisified functions
  const fsCopy = util.promisify(fs.copy);
  const fsExists = util.promisify(fs.exists);

  const copyElmReviewSrcJob = fsExists(elmReviewSrc)
    .then(() =>
      // Copy our code into the project folder if they don't already exist
      fsCopy(templateSrc, elmReviewSrc, {
        overwrite: true,
        filter: (src) => {
          const extension = path.extname(src);
          return (
            (!extension /* directory */ || extension === '.elm') &&
            path.basename(src) !== 'ReviewConfig.elm'
          );
        }
      })
    )
    .catch(
      // Our code already exists
      () => null
    );

  // Load review project's elm.json file contents
  const createElmJsonFile = templateDependencies
    .get(options, reviewElmJson.dependencies, reviewElmJsonPath)
    .then(async (dependencies) => {
      await fsEnsureDir(path.dirname(elmJsonPath));
      return writeElmJsonFile(options, elmReviewSrc, elmJsonPath, {
        ...reviewElmJson,
        dependencies
      });
    });

  return Promise.all([copyElmReviewSrcJob, createElmJsonFile]);
}

function writeElmJsonFile(options, elmReviewSrc, elmJsonPath, elmJson) {
  const fsWriteFile = util.promisify(fs.writeFile);

  const elmJsonWithSourceDirectories = updateSourceDirectories(
    options,
    elmReviewSrc,
    elmJson
  );

  return fsWriteFile(
    elmJsonPath,
    JSON.stringify(elmJsonWithSourceDirectories, null, 4)
  );
}

function updateSourceDirectories(options, elmReviewSrc, elmJson) {
  const userSrc = options.userSrc();
  const sourceDirectories = elmJson['source-directories']
    .map((directory) => path.resolve(userSrc, directory))
    .concat([path.resolve(elmReviewSrc)])
    .concat(
      options.localElmReviewSrc
        ? [path.resolve(userSrc, options.localElmReviewSrc)]
        : []
    );

  return {
    ...elmJson,
    'source-directories': sourceDirectories
  };
}

function compileElmProject(options, dest, elmModulePath, elmBinary) {
  const compileOptions = {
    cwd: path.join(dest, 'project'),
    output: elmModulePath,
    debug: Boolean(options.debug),
    optimize: !options.debug,
    verbose: false,
    warn: false,
    pathToElm: elmBinary,
    processOpts: {
      env: process.env,
      stdio: ['ignore', 'ignore', 'pipe']
    }
  };

  return new Promise((resolve, reject) => {
    const compileProcess = elmCompiler.compile(
      ['./elm-review-src/Elm/Review/Main.elm'],
      compileOptions
    );

    let stderr = '';
    if (compileProcess.stderr) {
      compileProcess.stderr.on('data', (data) => {
        stderr += data;
      });
    }

    compileProcess.on('close', (exitCode) => {
      if (exitCode === 0) {
        resolve();
      } else {
        const {title, message} = compilationError(options, stderr);
        if (options.report === 'json') {
          return reject(
            new errorMessage.CustomError(title, `${message}\n\n${stderr}`)
          );
        }

        // Re-running the compiler to print its errors in color.
        // We do this because piping stderr loses the color, which we use to
        // give different error messages based
        console.error(
          errorMessage.report(
            options,
            new errorMessage.CustomError(title, wrap(message, 80) + '\n\n')
          )
        );
        compileOptions.processOpts.stdio = ['ignore', 'ignore', 'inherit'];
        const compileProcessToGetColoredErrors = elmCompiler.compile(
          ['./elm-review-src/Elm/Review/Main.elm'],
          compileOptions
        );

        compileProcessToGetColoredErrors.on('close', () => {
          // eslint-disable-next-line unicorn/no-process-exit
          process.exit(1);
        });
      }
    });
  });
}

function compilationError(options, stderr) {
  if (stderr.includes('DEBUG REMNANTS')) {
    return {
      title: 'DEBUG IN CONFIGURATION',
      /* eslint-disable prettier/prettier */
      message: `You are using the ${chalk.yellow('Debug')} module in your configuration or rules, but I am compiling in optimized mode. Either remove those uses or run elm-review with ${chalk.yellow('--debug')}.`
      /* eslint-enable prettier/prettier */
    };
  }

  if (stderr.includes('MODULE NOT FOUND')) {
    return {
      title: 'MODULE NOT FOUND',
      /* eslint-disable prettier/prettier */
      message: `A module is missing in your configuration. Maybe you forgot to add some dependencies that contain the rules you wished to enable? If so, run ${chalk.cyanBright('elm install')} with the package name from inside ${chalk.yellowBright(options.userSrc())}.`
      /* eslint-enable prettier/prettier */
    };
  }

  return {
    title: 'INCORRECT CONFIGURATION',
    /* eslint-disable prettier/prettier */
    message: `An error occurred while compiling your configuration for ${chalk.greenBright('elm-review')}. I need your configuration to compile in order to know how to analyze your files. Hopefully the compiler error below will help you figure out how to fix it.`
    /* eslint-enable prettier/prettier */
  };
}

function validateElmReviewVersion(
  options,
  reviewElmJsonPath,
  elmReviewVersion
) {
  if (options.localElmReviewSrc) {
    return;
  }

  if (!elmReviewVersion) {
    throw new errorMessage.CustomError(
      /* eslint-disable prettier/prettier */
'MISSING ELM-REVIEW DEPENDENCY',
`\`${reviewElmJsonPath}\` does not include ${chalk.greenBright('jfmengels/elm-review')} in its direct dependencies.

Please add it by running ${chalk.cyanBright('elm install jfmengels/elm-review')} inside
of ${path.dirname(reviewElmJsonPath)}.`
      /* eslint-enable prettier/prettier */
    );
  }

  const [major, minor] = elmReviewVersion.split('.');
  if (major === '2' && minor < Number.parseInt('1', 10)) {
    throw new errorMessage.CustomError(
      /* eslint-disable prettier/prettier */
'UNSUPPORTED ELM-REVIEW VERSION',
`You are using ${chalk.greenBright('jfmengels/elm-review')} v${elmReviewVersion}, but I need it to be
2.1.0 <= v < 3.0.0.

Please upgrade your version by running
${chalk.cyanBright('npx elm-json install jfmengels/elm-review@2')} inside
of ${path.dirname(reviewElmJsonPath)}.`
      /* eslint-enable prettier/prettier */
    );
  }
}

module.exports = {build};

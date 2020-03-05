const path = require('path');
const util = require('util');
const crypto = require('crypto');
const chalk = require('chalk');
const fs = require('fs-extra');
const {hashElement} = require('folder-hash');
const elmCompiler = require('node-elm-compiler');
const {getElmBinary} = require('./elm-binary');
const templateDependencies = require('./template-dependencies');
const errorMessage = require('./error-message');

const fsEnsureDir = util.promisify(fs.ensureDir);
const fsReadJson = util.promisify(fs.readJson);

async function cachedBuild(debug, userSrc, reviewElmJsonPath, reviewElmJson) {
  const hashes = await Promise.all(
    reviewElmJson['source-directories']
      .map(directory =>
        hashElement(path.resolve(userSrc, directory), {
          folders: {exclude: ['.*', 'node_modules', 'elm-stuff']},
          files: {include: ['*.elm']},
          algo: 'md5'
        })
      )
      .concat(hashElement(reviewElmJsonPath, {algo: 'md5'}))
  );

  const hash = hashes
    .reduce((resHash, {hash}) => resHash.update(hash), crypto.createHash('md5'))
    .digest('hex');

  return debug ? `${hash}-debug` : hash;
}

async function build(options) {
  const projectToReview = options.projectToReview();
  const userSrc = options.userSrc();
  const reviewElmJsonPath = path.join(userSrc, 'elm.json');

  const reviewElmJson = await fsReadJson(reviewElmJsonPath).catch(error => {
    if (error.code === 'ENOENT') {
      return Promise.reject(
        new Error(
          /* eslint-disable prettier/prettier */
          errorMessage(
'INCORRECT CONFIGURATION',
`I could not find a review configuration. I was expecting to find an ${chalk.cyan('elm.json')} file and a ${chalk.cyan('ReviewConfig.elm')} file in ${chalk.cyan(path.dirname(reviewElmJsonPath))}.

I can help set you up with an initial configuration if you run ${chalk.cyan('elm-review init')}.`
          )
          /* eslint-enable prettier/prettier */
        )
      );
    }

    return Promise.reject(error);
  });

  const applicationHash = await cachedBuild(
    options.debug,
    userSrc,
    reviewElmJsonPath,
    reviewElmJson
  );

  const pathToApplicationDirectory = options.pathToApplicationDirectory(
    applicationHash
  );
  const binaryPath = path.resolve(pathToApplicationDirectory, 'main.js');
  if (fs.existsSync(binaryPath)) {
    if (options.debug) {
      console.log(`Review application is already built. Using ${binaryPath}`);
    }
  } else {
    if (options.debug) {
      console.log('Starting review application build');
    }

    await Promise.all([
      getElmBinary(options),
      createTemplateProject(
        options,
        pathToApplicationDirectory,
        projectToReview,
        reviewElmJson
      )
    ]).then(([elmBinary]) =>
      compileElmProject(
        options,
        pathToApplicationDirectory,
        binaryPath,
        elmBinary
      )
    );
  }

  return {
    elmModule: loadCompiledElmApp(binaryPath),
    reviewElmJsonPath,
    reviewElmJson
  };
}

function loadCompiledElmApp(binaryPath) {
  const oldConsoleWarn = console.warn;
  const regex = /^Compiled in DE(BUG|V) mode/;
  // $FlowFixMe
  console.warn = function(...args) {
    if (args.length === 1 && regex.test(args[0])) return;
    return oldConsoleWarn.apply(console, args);
  };

  // $FlowFixMe
  return require(binaryPath);
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
  const fsRemove = util.promisify(fs.remove);

  const copyElmReviewSrcJob = fsExists(elmReviewSrc)
    .then(() =>
      // Copy our code into the project folder if they don't already exist
      // TODO Performance: Copy only the Elm files
      fsCopy(templateSrc, elmReviewSrc, {
        overwrite: true
      }).then(() =>
        // Delete the ReviewConfig that we use for development
        // TODO Performance: Don't copy ReviewConfig.elm in the first place
        fsRemove(path.join(elmReviewSrc, 'ReviewConfig.elm'))
      )
    )
    .catch(
      // Our code already exists
      () => null
    );

  // Load review project's elm.json file contents
  const createElmJsonFile = templateDependencies
    .get(options, reviewElmJson.dependencies, reviewElmJsonPath)
    .then(async dependencies => {
      if (options.localElmReviewSrc) {
        delete dependencies.direct['jfmengels/elm-review'];
      }

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
    .map(directory => path.resolve(userSrc, directory))
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

function compileElmProject(options, dest, binaryPath, elmBinary) {
  const compileOptions = {
    cwd: path.join(dest, 'project'),
    output: binaryPath,
    debug: Boolean(options.debug),
    optimize: !options.debug,
    verbose: false,
    warn: false,
    pathToElm: elmBinary,
    processOpts: {
      env: process.env,
      stdio: ['ignore', 'ignore', 'inherit']
    }
  };

  return new Promise((resolve, reject) => {
    const compileProcess = elmCompiler.compile(
      ['./elm-review-src/Elm/Review/Main.elm'],
      compileOptions
    );

    compileProcess.on('close', exitCode => {
      if (exitCode === 0) {
        resolve();
      } else {
        reject(
          new Error(
            /* eslint-disable prettier/prettier */
            errorMessage(
'INCORRECT CONFIGURATION',
`An error occurred while compiling your configuration for \`elm-review\`.
I need your configuration to compile in order to know how to analyze your files.
Hopefully the compiler error above will help you figure out how to fix it.

If you see an error about the use of ${chalk.yellow('Debug')}, then you likely use it somewhere,
which is not allowed by default. You may want to run elm-review with ${chalk.yellow('--debug')}.

If that is not the case, maybe you forgot to add some dependencies that contain
the rules you wished to enable?`
            ) /* eslint-enable prettier/prettier */
          )
        );
      }
    });
  });
}

module.exports = {build};

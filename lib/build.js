const path = require('path');
const util = require('util');
const crypto = require('crypto');
const temp = require('temp');
const chalk = require('chalk');
const fs = require('fs-extra');
const wrap = require('wrap-ansi');
const {hashElement} = require('folder-hash');
const elmCompiler = require('../vendor/node-elm-compiler');
const {getElmBinary} = require('./elm-binary');
const Debug = require('./debug');
const Spinner = require('./spinner');
const Anonymize = require('./anonymize');
const MinVersion = require('./min-version');
const ErrorMessage = require('./error-message');
const RemoteTemplate = require('./remote-template');
const TemplateDependencies = require('./template-dependencies');

const fsEnsureDir = util.promisify(fs.ensureDir);
const fsReadJson = util.promisify(fs.readJson);
const fsWriteFile = util.promisify(fs.writeFile);

const templateSrc = path.join(__dirname, '../template/src');
const parseElmFolder = path.join(__dirname, '../parseElm');
const astCodecSrc = path.join(__dirname, '../ast-codec/src');

async function cachedBuild(options, userSrc, reviewElmJsonPath, reviewElmJson) {
  const sourceDirectoriesHashes = reviewElmJson['source-directories'].map(
    (directory) =>
      hashElement(path.resolve(userSrc, directory), {
        folders: {exclude: ['.*', 'elm-stuff']},
        files: {include: ['*.elm']},
        algo: 'md5'
      })
  );
  const reviewElmJsonHash = hashElement(reviewElmJsonPath, {algo: 'md5'});

  const localElmReviewSourceHashes = options.localElmReviewSrc
    ? [
        hashElement(path.resolve(userSrc, options.localElmReviewSrc), {
          folders: {exclude: ['.*', 'elm-stuff']},
          files: {include: ['*.elm']},
          algo: 'md5'
        })
      ]
    : [];

  const hashes = await Promise.all([
    ...sourceDirectoriesHashes,
    ...localElmReviewSourceHashes,
    reviewElmJsonHash
  ]);

  const hash = hashes
    .reduce(
      (resultHash, {hash}) => resultHash.update(hash),
      crypto.createHash('md5')
    )
    .digest('hex');

  return `${hash}${options.debug ? '-debug' : ''}`;
}

function build(options) {
  if (options.template) {
    if (options.usedConfig) {
      throw new ErrorMessage.CustomError(
        /* eslint-disable prettier/prettier */
      'INCOMPATIBLE FLAGS',
      `You used both ${chalk.cyan('--config')} and ${chalk.cyan('--template')}, but these flags can't be used together.

Please remove one of them and try re-running.`,
        /* eslint-enable prettier/prettier */
      );
    }

    return buildFromGitHubTemplate(options);
  }

  return buildLocalProject(options);
}

async function buildLocalProject(options) {
  const userSrc = options.userSrc();
  const reviewElmJsonPath = path.join(userSrc, 'elm.json');

  const reviewElmJson = await fsReadJson(reviewElmJsonPath).catch((error) => {
    if (error.code === 'ENOENT') {
      return Promise.reject(
        new ErrorMessage.CustomError(
          /* eslint-disable prettier/prettier */
'INCORRECT CONFIGURATION',
`I could not find a review configuration. I was expecting to find an ${chalk.yellow('elm.json')} file and a ${chalk.cyan('ReviewConfig.elm')} file in ${chalk.cyan(path.dirname(reviewElmJsonPath))}${chalk.cyan('/')}.

I can help set you up with an initial configuration if you run ${chalk.magenta('elm-review init')}.`,
options.elmJsonPath
          /* eslint-enable prettier/prettier */
        )
      );
    }

    return Promise.reject(error);
  });

  validateElmReviewVersion(options, reviewElmJsonPath, reviewElmJson);

  const appHash = await cachedBuild(
    options,
    userSrc,
    reviewElmJsonPath,
    reviewElmJson
  );

  let elmModulePath = options.elmModulePath(appHash);
  if (!options.forceBuild && fs.existsSync(elmModulePath)) {
    Debug.log(
      `Review application is already built. Using ${Anonymize.path(
        options,
        elmModulePath
      )}`
    );
  } else {
    const buildFolder = temp.mkdirSync('elm-review-app');
    Debug.log('Starting review application build');

    const buildResult = await Promise.all([
      getElmBinary(options),
      createTemplateProject(
        options,
        reviewElmJsonPath,
        userSrc,
        buildFolder,
        reviewElmJson
      )
    ]).then(([elmBinary]) => {
      Debug.log('Compiling review application');
      return compileElmProject(
        options,
        path.join(buildFolder, 'project'),
        elmModulePath,
        [`${templateSrc}/Elm/Review/Main.elm`],
        elmBinary
      );
    });

    if (buildResult) {
      Debug.log('Finished review application build');
    } else {
      elmModulePath = null;
    }
  }

  return {
    elmModulePath,
    reviewElmJsonPath,
    reviewElmJson
  };
}

async function buildFromGitHubTemplate(options) {
  Spinner.setText('Fetching template information');
  const commit = await RemoteTemplate.getRelevantCommit(
    options,
    options.template
  );
  const reviewElmJson = await RemoteTemplate.getRemoteElmJson(
    options,
    options.template,
    options.pathToTemplateElmJson(commit),
    commit
  );
  Debug.log(`Commit is: ${commit}`);

  let elmModulePath = options.templateElmModulePath(commit);
  if (fs.existsSync(elmModulePath)) {
    Debug.log(
      `Review application is already built. Using ${Anonymize.path(
        options,
        elmModulePath
      )}`
    );

    Spinner.succeed();
  } else {
    const reviewElmJsonPath = options.pathToTemplateElmJson(commit);

    validateElmReviewVersion(options, reviewElmJsonPath, reviewElmJson);

    const buildFolder = temp.mkdirSync('elm-review-app');

    Spinner.setText('Downloading configuration files');
    // Download all files from the template
    await RemoteTemplate.downloadSourceDirectories(
      options,
      options.template,
      commit,
      buildFolder,
      reviewElmJson
    );

    Debug.log('Starting template review application build');

    Spinner.setText('Building review application');

    const reviewElmJsonWithReplacedParentDirectories = {
      ...reviewElmJson,
      'source-directories': reviewElmJson['source-directories'].map((dir) =>
        dir.split('..').join('parent')
      )
    };
    const buildResult = await Promise.all([
      getElmBinary(options),
      createTemplateProject(
        options,
        reviewElmJsonPath,
        buildFolder,
        buildFolder,
        reviewElmJsonWithReplacedParentDirectories
      )
    ]).then(([elmBinary]) => {
      Debug.log('Compiling template review application');
      return compileElmProject(
        options,
        path.join(buildFolder, 'project'),
        elmModulePath,
        [`${templateSrc}/Elm/Review/Main.elm`],
        elmBinary
      );
    });

    if (buildResult) {
      Debug.log('Finished template review application build');
    } else {
      elmModulePath = null;
    }

    Spinner.succeed('Build finished! Now reviewing your project...');
  }

  return {
    elmModulePath,
    reviewElmJsonPath: null,
    reviewElmJson
  };
}

async function createTemplateProject(
  options,
  reviewElmJsonPath,
  userSrc,
  dest,
  reviewElmJson
) {
  // Destination directories
  const projectFolder = path.join(dest, 'project');
  const elmJsonPath = path.join(projectFolder, 'elm.json');

  // Load review project's elm.json file contents
  const dependencies = await TemplateDependencies.get(
    options,
    reviewElmJson.dependencies,
    reviewElmJsonPath
  );
  await fsEnsureDir(path.dirname(elmJsonPath));
  return writeElmJsonFile(options, userSrc, elmJsonPath, {
    ...reviewElmJson,
    dependencies
  });
}

function writeElmJsonFile(options, userSrc, elmJsonPath, elmJson) {
  const elmJsonWithSourceDirectories = updateSourceDirectories(
    options,
    userSrc,
    elmJson
  );

  return fsWriteFile(
    elmJsonPath,
    JSON.stringify(elmJsonWithSourceDirectories, null, 4)
  );
}

function updateSourceDirectories(options, userSrc, elmJson) {
  let sourceDirectories = elmJson['source-directories']
    .map((directory) => path.resolve(userSrc, directory))
    .concat([path.resolve(templateSrc), path.resolve(astCodecSrc)]);

  if (options.localElmReviewSrc) {
    sourceDirectories = unique(
      sourceDirectories.concat(
        path.resolve(process.cwd(), options.localElmReviewSrc)
      )
    );
  }

  return {
    ...elmJson,
    'source-directories': sourceDirectories
  };
}

function unique(array) {
  return [...new Set(array)];
}

function compileElmProject(
  options,
  dest,
  elmModulePath,
  compileTargets,
  elmBinary
) {
  const compileOptions = {
    cwd: dest,
    output: path.resolve(elmModulePath),
    debug: Boolean(options.debug),
    optimize: !options.debug,
    verbose: false,
    warn: false,
    report: 'json',
    pathToElm: elmBinary,
    processOpts: {
      env: process.env,
      stdio: ['ignore', 'ignore', 'pipe']
    }
  };

  return new Promise((resolve) => {
    const compileProcess = elmCompiler.compile(compileTargets, compileOptions);

    let stderr = '';
    if (compileProcess.stderr) {
      compileProcess.stderr.on('data', (data) => {
        stderr += data;
      });
    }

    compileProcess.on('close', (exitCode) => {
      if (exitCode === 0) {
        resolve(elmModulePath);
      } else {
        const {title, message} = compilationError(options, stderr);
        if (options.report === 'json') {
          console.log(
            ErrorMessage.report(
              options,
              new ErrorMessage.CustomError(title, `${message}\n\n${stderr}`)
            )
          );
          return resolve(null);
        }

        // Re-running the compiler to print its errors in color.
        // We do this because piping stderr loses the color, which we use to
        // give different error messages based
        console.log(
          ErrorMessage.report(
            options,
            new ErrorMessage.CustomError(title, wrap(message, 80) + '\n\n')
          )
        );
        compileOptions.processOpts.stdio = ['ignore', 'ignore', 'inherit'];
        compileOptions.report = undefined;
        const compileProcessToGetColoredErrors = elmCompiler.compile(
          compileTargets,
          compileOptions
        );

        compileProcessToGetColoredErrors.on('close', () => {
          if (options.watch) {
            return resolve(null);
          }

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
      message: `A module is missing in your configuration. Maybe you forgot to add some dependencies that contain the rules you wished to enable? If so, run ${chalk.magenta('elm install')} with the package name from inside ${chalk.yellow(options.userSrc(null))}.`
      /* eslint-enable prettier/prettier */
    };
  }

  if (options.report === 'json') {
    if (options.debug) {
      console.log(JSON.stringify(JSON.parse(stderr), null, 2));
    } else {
      console.log(stderr);
    }

    // TODO Handle this better
    // eslint-disable-next-line unicorn/no-process-exit
    process.exit(1);
  }

  return {
    title: 'CONFIGURATION COMPILATION ERROR',
    /* eslint-disable prettier/prettier */
    message: `Errors occurred while compiling your configuration for ${chalk.greenBright('elm-review')}. I need your configuration to compile in order to know how to analyze your files. Hopefully the compiler error below will help you figure out how to fix it.`
    /* eslint-enable prettier/prettier */
  };
}

function validateElmReviewVersion(options, reviewElmJsonPath, reviewElmJson) {
  if (options.localElmReviewSrc) {
    return;
  }

  if (reviewElmJson.type !== 'application') {
    let pathToElmJson = reviewElmJsonPath;
    if (options.template) {
      const {repoName, pathToFolder = ''} = options.template;
      const pathToElmJsonInRepo = `${pathToFolder}/elm.json`
        .split('//')
        .join('/');
      pathToElmJson = `${repoName}'s ${pathToElmJsonInRepo}`;
    }

    throw new ErrorMessage.CustomError(
      /* eslint-disable prettier/prettier */
      'REVIEW CONFIG IS NOT AN APPLICATION',
      `I wanted to use ${chalk.yellow(pathToElmJson)} as the basis for the configuration, and I expected it to be an "application", but it wasn't.

I think it likely that you are pointing to an incorrect configuration file. Please check the path to your configuration again.`
      /* eslint-enable prettier/prettier */
    );
  }

  const elmReviewVersion =
    reviewElmJson.dependencies.direct['jfmengels/elm-review'];

  if (!elmReviewVersion) {
    if (options.template) {
      throw new ErrorMessage.CustomError(
        /* eslint-disable prettier/prettier */
'MISSING ELM-REVIEW DEPENDENCY',
`The template's configuration does not include ${chalk.greenBright('jfmengels/elm-review')} in its direct dependencies.

Maybe you chose the wrong template, or the template is malformed. If the latter is the case, please inform the template author.`
        /* eslint-enable prettier/prettier */
      );
    }

    throw new ErrorMessage.CustomError(
      /* eslint-disable prettier/prettier */
'MISSING ELM-REVIEW DEPENDENCY',
`${chalk.yellow(reviewElmJsonPath)} does not include ${chalk.greenBright('jfmengels/elm-review')} in its direct dependencies.

Please add it by running ${chalk.magenta('elm install jfmengels/elm-review')} inside
of ${chalk.yellow(path.dirname(reviewElmJsonPath))}.`
      /* eslint-enable prettier/prettier */
    );
  }

  MinVersion.validate(options, reviewElmJsonPath, elmReviewVersion);
}

async function buildElmParser(options, reviewElmJson) {
  const elmSyntaxVersion =
    reviewElmJson.dependencies.direct['stil4m/elm-syntax'] ||
    reviewElmJson.dependencies.indirect['stil4m/elm-syntax'];
  const elmParserPath = options.elmParserPath(elmSyntaxVersion);
  if (fs.existsSync(elmParserPath)) {
    Debug.log(`Parser app for elm-syntax v${elmSyntaxVersion} already exists.`);
    return;
  }

  Debug.log(`Building parser app for elm-syntax v${elmSyntaxVersion}`);

  const buildFolder = temp.mkdirSync('elm-parser-app');
  const parseElmElmJsonPath = path.resolve(parseElmFolder, 'elm.json');
  const parseElmElmJson = await fsReadJson(parseElmElmJsonPath).catch(
    (error) => {
      if (error.code === 'ENOENT') {
        return Promise.reject(
          new ErrorMessage.CustomError(
          /* eslint-disable prettier/prettier */
'UNEXPECTED INTERNAL ERROR',
`I was expecting to find the "parseElm" project at ${chalk.cyan(parseElmElmJsonPath)} but could not find it.

Please open an issue at the following link:
https://github.com/jfmengels/node-elm-review/issues/new
`,
options.elmJsonPath
          /* eslint-enable prettier/prettier */
          )
        );
      }

      return Promise.reject(error);
    }
  );

  const dependencies = await TemplateDependencies.addElmSyntax(
    options,
    parseElmElmJsonPath,
    elmSyntaxVersion
  );

  await Promise.all([
    fsWriteFile(
      path.resolve(buildFolder, 'elm.json'),
      JSON.stringify(
        {
          ...parseElmElmJson,
          dependencies,
          'source-directories': parseElmElmJson[
            'source-directories'
          ].map((dir) => path.resolve(parseElmFolder, dir))
        },
        null,
        2
      ),

      // Needed when the user has `"type": "module"` in their package.json.
      // Our output is CommonJS.
      fsEnsureDir(options.generatedCodePackageJson()).then(() =>
        fsWriteFile(
          path.join(options.generatedCodePackageJson(), 'package.json'),
          JSON.stringify({type: 'commonjs'})
        )
      )
    )
  ]);

  return compileElmProject(
    options,
    buildFolder,
    elmParserPath,
    [`${parseElmFolder}/src/ParseMain.elm`],
    await getElmBinary(options)
  );
}

module.exports = {
  build,
  buildElmParser
};

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const chalk = require('chalk');
// eslint-disable-next-line @typescript-eslint/ban-ts-comment
// @ts-ignore: wrap-ansi includes type definitions since version 8, but it also requires node 12
const wrap = require('wrap-ansi');
const {hashElement} = require('folder-hash');
const elmCompiler = require('../vendor/node-elm-compiler');
const {getElmBinary} = require('./elm-binary');
const Debug = require('./debug');
const FS = require('./fs-wrapper');
const Spinner = require('./spinner');
const Anonymize = require('./anonymize');
const Benchmark = require('./benchmark');
const OptimizeJs = require('./optimize-js');
const MinVersion = require('./min-version');
const ErrorMessage = require('./error-message');
const RemoteTemplate = require('./remote-template');
const TemplateDependencies = require('./template-dependencies');
const exit = require('../vendor/exit');

/**
 * @typedef { import("./types/options").Options } Options
 * @typedef { import("./types/options").Template } Template
 * @typedef { import("./types/build").BuildResult } BuildResult
 * @typedef { import("./types/build").AppHash } AppHash
 * @typedef { import("./types/content").ApplicationElmJson } ApplicationElmJson
 * @typedef { import("./types/elm-version").ElmVersion } ElmVersion
 * @typedef { import("./types/path").Path } Path
 */

const templateSrc = path.join(__dirname, '../template/src');
const parseElmFolder = path.join(__dirname, '../parseElm');
const astCodecSrc = path.join(__dirname, '../ast-codec/src');

/**
 * Get the hash associated to the current review application.
 * This is either retrieved from a cache or computed.
 * @param {Options} options
 * @param {Path} userSrc
 * @param {Path} reviewElmJsonPath
 * @param {Path[]} sourceDirectories
 * @returns {Promise<AppHash>}
 */
async function cachedBuild(
  options,
  userSrc,
  reviewElmJsonPath,
  sourceDirectories
) {
  const sourceDirectoriesHashes = sourceDirectories.map((directory) =>
    hashElement(path.resolve(userSrc, directory), {
      folders: {exclude: ['.*', 'elm-stuff']},
      files: {include: ['*.elm']},
      algo: 'md5'
    }).catch(() => null)
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
    .filter(Boolean)
    .reduce(
      (resultHash, {hash}) => resultHash.update(hash),
      crypto.createHash('md5')
    )
    .digest('hex');

  return `${hash}${options.debug ? '-debug' : ''}`;
}

/**
 * Build a review application.
 * @param {Options} options
 * @returns {Promise<BuildResult>}
 */
function build(options) {
  if (options.template) {
    if (options.usedConfig) {
      throw new ErrorMessage.CustomError(
        'INCOMPATIBLE FLAGS',
        // prettier-ignore
        `You used both ${chalk.cyan('--config')} and ${chalk.cyan('--template')}, but these flags can't be used together.

Please remove one of them and try re-running.`
      );
    }

    return buildFromGitHubTemplate(options, options.template);
  }

  return buildLocalProject(options);
}

/**
 * Build a review application from a local configuration.
 * @param {Options} options
 * @returns {Promise<BuildResult>}
 */
async function buildLocalProject(options) {
  const userSrc = options.userSrc();
  const reviewElmJsonPath = path.join(userSrc, 'elm.json');

  const reviewElmJson = await FS.readJsonFile(reviewElmJsonPath).catch(
    (error) => {
      if (error.code === 'ENOENT') {
        return Promise.reject(
          new ErrorMessage.CustomError(
            // prettier-ignore
            'INCORRECT CONFIGURATION',
            // prettier-ignore
            `I could not find a review configuration. I was expecting to find an ${chalk.yellow('elm.json')} file and a ${chalk.cyan('ReviewConfig.elm')} file in ${chalk.cyan(path.dirname(reviewElmJsonPath))}${chalk.cyan('/')}.

I can help set you up with an initial configuration if you run ${chalk.magenta('elm-review init')}.`,
            options.elmJsonPath
          )
        );
      }

      return Promise.reject(error);
    }
  );

  validateElmReviewVersion(options, reviewElmJsonPath, reviewElmJson);

  Benchmark.start(options, 'Computing app hash');
  const appHash = await cachedBuild(
    options,
    userSrc,
    reviewElmJsonPath,
    reviewElmJson['source-directories']
  );
  Benchmark.end(options, 'Computing app hash');

  /** @type {Path | null} */
  let elmModulePath = options.elmModulePath(appHash);
  if (!options.forceBuild && fs.existsSync(elmModulePath)) {
    Debug.log(
      `Review application is already built. Using ${Anonymize.path(
        options,
        elmModulePath
      )}`
    );
  } else {
    const buildFolder = path.join(options.buildFolder(), 'review-project');
    Debug.log('Starting review application build');

    const buildResult = await Promise.all([
      getElmBinary(options),
      createTemplateProject(options, userSrc, buildFolder, reviewElmJson)
    ]).then(([elmBinary]) => {
      Debug.log('Compiling review application');
      Benchmark.start(options, 'Compile review project');
      return compileElmProject(
        options,
        buildFolder,
        elmModulePath,
        [`${templateSrc}/Elm/Review/Main.elm`],
        elmBinary,
        true
      );
    });
    Benchmark.end(options, 'Compile review project');

    if (buildResult) {
      Debug.log('Finished review application build');
    } else {
      elmModulePath = null;
    }
  }

  return {
    elmModulePath,
    reviewElmJsonPath,
    reviewElmJson,
    appHash
  };
}

/**
 * Build a review application from a remote GitHub template configuration.
 * @param {Options} options
 * @param {Template} template
 * @returns {Promise<BuildResult>}
 */
async function buildFromGitHubTemplate(options, template) {
  Spinner.setText('Fetching template information');
  const commit = await RemoteTemplate.getRelevantCommit(
    options,
    options.template
  );
  const reviewElmJson = await RemoteTemplate.getRemoteElmJson(
    options,
    template,
    options.pathToTemplateElmJson(commit),
    commit,
    false
  );
  Debug.log(`Commit is: ${commit}`);

  /** @type {Path | null} */
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

    const buildFolder = path.join(options.buildFolder(), 'template');

    Spinner.setText('Downloading configuration files');
    // Download all files from the template
    await RemoteTemplate.downloadSourceDirectories(
      options,
      template,
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
        buildFolder,
        path.join(buildFolder, 'project'),
        reviewElmJsonWithReplacedParentDirectories
      )
    ]).then(([elmBinary]) => {
      Debug.log('Compiling template review application');
      return compileElmProject(
        options,
        path.join(buildFolder, 'project'),
        elmModulePath,
        [`${templateSrc}/Elm/Review/Main.elm`],
        elmBinary,
        true
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
    appHash: `${template.pathToFolder}/${commit}`,
    elmModulePath,
    reviewElmJsonPath: null,
    reviewElmJson
  };
}

/**
 * Create a local temporary project to build an Elm application in.
 * @param {Options} options
 * @param {Path} userSrc
 * @param {Path} projectFolder
 * @param {ApplicationElmJson} reviewElmJson
 * @returns {Promise<void>}
 */
async function createTemplateProject(
  options,
  userSrc,
  projectFolder,
  reviewElmJson
) {
  Benchmark.start(options, 'Create template project');
  // Destination directories
  const elmJsonPath = path.join(projectFolder, 'elm.json');

  // Load review project's elm.json file contents
  const [previousElmJson, dependencies] = await Promise.all([
    FS.readFile(elmJsonPath).catch(() => null),
    TemplateDependencies.addRequiredDependencies(options, reviewElmJson)
  ]);
  const finalElmJson = updateSourceDirectories(options, userSrc, {
    ...reviewElmJson,
    dependencies,
    'test-dependencies': {direct: {}, indirect: {}}
  });
  const finalElmJsonAsString = JSON.stringify(finalElmJson, null, 4);
  if (previousElmJson !== finalElmJsonAsString) {
    // We only write the elm.json file if we detect that it's different from the one in the build folder.
    // This improves performance because if the Elm compiler detects that the elm.json file has not changed,
    // it will be using its cached assets.
    await FS.mkdirp(projectFolder);
    await FS.writeFile(elmJsonPath, finalElmJsonAsString);
  }

  Benchmark.end(options, 'Create template project');
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

/**
 * @typedef {Object} CompileOptions
 * @property {string} cwd
 * @property {string} output
 * @property {boolean} debug
 * @property {boolean} optimize
 * @property {boolean} verbose
 * @property {boolean} warn
 * @property {'json' | undefined} report
 * @property {string} pathToElm
 * @property {ProcessOptions} processOpts
 */

/**
 * @typedef {Object} ProcessOptions
 * @property {NodeJS.ProcessEnv} env
 * @property {('ignore' | 'inherit' | 'pipe')[]} stdio
 */

function compileElmProject(
  options,
  dest,
  elmModulePath,
  compileTargets,
  elmBinary,
  isReviewAppApp
) {
  /** @type {CompileOptions} */
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

          exit(1);
        });
      }
    });
  }).then((elmModulePath) =>
    OptimizeJs.optimize(options, elmModulePath, isReviewAppApp)
  );
}

function compilationError(options, stderr) {
  if (stderr.includes('DEBUG REMNANTS')) {
    return {
      title: 'DEBUG IN CONFIGURATION',
      // prettier-ignore
      message: `You are using the ${chalk.yellow('Debug')} module in your configuration or rules, but I am compiling in optimized mode. Either remove those uses or run elm-review with ${chalk.yellow('--debug')}.`
    };
  }

  if (stderr.includes('MODULE NOT FOUND')) {
    return {
      title: 'MODULE NOT FOUND',
      // prettier-ignore
      message: `A module is missing in your configuration. Maybe you forgot to add some dependencies that contain the rules you wished to enable? If so, run ${chalk.magenta('elm install')} with the package name from inside ${chalk.yellow(options.userSrc(null))}.`
    };
  }

  if (options.report === 'json') {
    if (options.debug) {
      console.log(JSON.stringify(JSON.parse(stderr), null, 2));
    } else {
      console.log(stderr);
    }

    // TODO Handle this better

    exit(1);
  }

  return {
    title: 'CONFIGURATION COMPILATION ERROR',
    // prettier-ignore
    message: `Errors occurred while compiling your configuration for ${chalk.greenBright('elm-review')}. I need your configuration to compile in order to know how to analyze your files. Hopefully the compiler error below will help you figure out how to fix it.`
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
      'REVIEW CONFIG IS NOT AN APPLICATION',
      // prettier-ignore
      `I wanted to use ${chalk.yellow(pathToElmJson)} as the basis for the configuration, and I expected it to be an "application", but it wasn't.

I think it likely that you are pointing to an incorrect configuration file. Please check the path to your configuration again.`
    );
  }

  const elmReviewVersion =
    reviewElmJson.dependencies.direct['jfmengels/elm-review'];

  if (!elmReviewVersion) {
    if (options.template) {
      throw new ErrorMessage.CustomError(
        // prettier-ignore
        'MISSING ELM-REVIEW DEPENDENCY',
        // prettier-ignore
        `The template's configuration does not include ${chalk.greenBright('jfmengels/elm-review')} in its direct dependencies.

Maybe you chose the wrong template, or the template is malformed. If the latter is the case, please inform the template author.`
      );
    }

    throw new ErrorMessage.CustomError(
      // prettier-ignore
      'MISSING ELM-REVIEW DEPENDENCY',
      // prettier-ignore
      `${chalk.yellow(reviewElmJsonPath)} does not include ${chalk.greenBright('jfmengels/elm-review')} in its direct dependencies.

Please add it by running ${chalk.magenta('elm install jfmengels/elm-review')} inside
of ${chalk.yellow(path.dirname(reviewElmJsonPath))}.`
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

  const buildFolder = options.buildFolderForParserApp();

  const [elmBinary] = await Promise.all([
    getElmBinary(options),
    createParserElmJsonFile(
      options,
      buildFolder,
      reviewElmJson['elm-version'],
      elmSyntaxVersion
    ),
    // Needed when the user has `"type": "module"` in their package.json.
    // Our output is CommonJS.
    FS.mkdirp(options.generatedCodePackageJson()).then(() =>
      FS.writeFile(
        path.join(options.generatedCodePackageJson(), 'package.json'),
        '{"type":"commonjs"}'
      )
    )
  ]);

  return compileElmProject(
    options,
    buildFolder,
    elmParserPath,
    [`${parseElmFolder}/src/ParseMain.elm`],
    elmBinary,
    false
  );
}

/** Create `elm.json` file for the parser application, which will use the exact same version
 * of `stil4m/elm-syntax` as the review application.
 *
 * @param {Options} options
 * @param {Path} buildFolder
 * @param {ElmVersion} elmVersion
 * @param {ElmVersion} elmSyntaxVersion
 * @return {Promise<void>}
 */
async function createParserElmJsonFile(
  options,
  buildFolder,
  elmVersion,
  elmSyntaxVersion
) {
  /** @type {ApplicationElmJson} */
  const parseElmElmJson = await TemplateDependencies.addElmSyntax(
    options,
    elmVersion,
    elmSyntaxVersion
  );

  parseElmElmJson['source-directories'] = parseElmElmJson[
    'source-directories'
  ].map((dir) => path.resolve(parseElmFolder, dir));

  await FS.mkdirp(buildFolder);
  return FS.writeFile(
    path.resolve(buildFolder, 'elm.json'),
    JSON.stringify(parseElmElmJson, null, 2)
  );
}

module.exports = {
  build,
  buildElmParser
};

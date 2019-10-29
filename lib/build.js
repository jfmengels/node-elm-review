const path = require('path');
const util = require('util');
const chalk = require('chalk');
const fs = require('fs-extra');
const elmCompiler = require('node-elm-compiler');
const getElmBinary = require('./elm-binary');
const dependencies = require('./dependencies');
const errorMessage = require('./error-message');

async function build(args, packageJson, projectToReview) {
  const generatedCodeDir = path.join(
    'elm-stuff',
    'generated-code',
    'jfmengels',
    'elm-review',
    packageJson.version
  );
  const dest = path.join(projectToReview, generatedCodeDir);
  const binaryPath = path.resolve(dest, 'main.js');
  await Promise.all([
    getElmBinary(args),
    createTemplateProject(args, dest, projectToReview)
  ]).then(([elmBinary]) =>
    compileElmProject(args, dest, binaryPath, elmBinary)
  );
  return loadCompiledElmApp(binaryPath);
}

function loadCompiledElmApp(binaryPath) {
  const oldConsoleWarn = console.warn;
  // $FlowFixMe
  console.warn = function(...args) {
    if (args.length === 1 && args[0].indexOf('Compiled in DEV mode') === 0)
      return;
    return oldConsoleWarn.apply(console, args);
  };

  // $FlowFixMe
  return require(binaryPath);
}

async function createTemplateProject(args, dest, projectToReview) {
  // Source directories
  const templateSrc = path.join(__dirname, '../template/src');
  const userSrc = args.config
    ? path.join(process.cwd(), args.config)
    : path.join(projectToReview, 'review');
  const userElmJson = path.join(userSrc, 'elm.json');

  // Destination directories
  const projectFolder = path.join(dest, 'project');
  const elmJsonPath = path.join(projectFolder, 'elm.json');
  const elmReviewSrc = path.join(projectFolder, 'elm-review-src');

  // Promisified functions
  const fsReadJson = util.promisify(fs.readJson);
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
  const createElmJsonFile = Promise.all([
    fsReadJson(userElmJson).catch(error => {
      if (error.code === 'ENOENT') {
        return Promise.reject(
          new Error(
            /* eslint-disable prettier/prettier */
            errorMessage(
'INCORRECT CONFIGURATION',
`I could not find a review configuration. I was expecting to find an ${chalk.cyan('elm.json')} file and a ${chalk.cyan('ReviewConfig.elm')} file in ${chalk.cyan(path.dirname(userElmJson))}.

I can help set you up with an initial configuration if you run ${chalk.cyan('elm-review init')}.`
            )
            /* eslint-enable prettier/prettier */
          )
        );
      }

      return Promise.reject(error);
    }),
    dependencies.get(userElmJson)
  ]).then(([elmJson, dependencies]) => {
    elmJson.dependencies = dependencies;
    return writeElmJsonFile(userSrc, elmReviewSrc, elmJsonPath, elmJson);
  });
  return Promise.all([copyElmReviewSrcJob, createElmJsonFile]);
}

function writeElmJsonFile(userSrc, elmReviewSrc, elmJsonPath, elmJson) {
  const fsWriteFile = util.promisify(fs.writeFile);

  // Update source-directories in the project's elm.json
  elmJson['source-directories'] = elmJson['source-directories']
    .map(directory => path.resolve(userSrc, directory))
    .concat([path.resolve(elmReviewSrc)]);

  return fsWriteFile(elmJsonPath, JSON.stringify(elmJson, null, 4));
}

function compileElmProject(args, dest, binaryPath, elmBinary) {
  const compileOptions = {
    cwd: path.join(dest, 'project'),
    output: binaryPath,
    debug: Boolean(args.debug),
    optimize: !args.debug,
    verbose: false,
    warn: false,
    pathToElm: elmBinary,
    processOpts: {
      env: process.env,
      stdio: ['ignore', 'ignore', process.stderr]
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

const path = require('path');
const util = require('util');
const chalk = require('chalk');
const fs = require('fs-extra');
const elmCompiler = require('node-elm-compiler');
const getElmBinary = require('./elm-binary');
const dependencies = require('./dependencies');
const errorMessage = require('./error-message');

async function build(args, packageJson, projectToLint) {
  const generatedCodeDir = path.join(
    'elm-stuff',
    'generated-code',
    'jfmengels',
    'elm-lint',
    packageJson.version
  );
  const dest = path.join(projectToLint, generatedCodeDir);
  const binaryPath = path.resolve(dest, 'main.js');
  await Promise.all([
    getElmBinary(args),
    createTemplateProject(args, dest, projectToLint)
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

async function createTemplateProject(args, dest, projectToLint) {
  // Source directories
  const templateSrc = path.join(__dirname, '../template/src');
  const userSrc = args.config
    ? path.join(process.cwd(), args.config)
    : path.join(projectToLint, 'lint');
  const userElmJson = path.join(userSrc, 'elm.json');

  // Destination directories
  const projectFolder = path.join(dest, 'project');
  const elmJsonPath = path.join(projectFolder, 'elm.json');
  const elmLintSrc = path.join(projectFolder, 'elm-lint-src');

  // Promisified functions
  const fsReadJson = util.promisify(fs.readJson);
  const fsCopy = util.promisify(fs.copy);
  const fsExists = util.promisify(fs.exists);
  const fsRemove = util.promisify(fs.remove);

  const copyElmLintSrcJob = fsExists(elmLintSrc)
    .then(() =>
      // Copy our code into the project folder if they don't already exist
      // TODO Performance: Copy only the Elm files
      fsCopy(templateSrc, elmLintSrc, {
        overwrite: true
      }).then(() =>
        // Delete the LintConfig that we use for development
        // TODO Performance: Don't copy LintConfig.elm in the first place
        fsRemove(path.join(elmLintSrc, 'LintConfig.elm'))
      )
    )
    .catch(
      // Our code already exists
      () => null
    );

  // Load lint project's elm.json file contents
  const createElmJsonFile = Promise.all([
    fsReadJson(userElmJson).catch(error => {
      if (error.code === 'ENOENT') {
        return Promise.reject(
          new Error(
            /* eslint-disable prettier/prettier */
            errorMessage(
'INCORRECT CONFIGURATION',
`I could not find a lint configuration. I was expecting to find an ${chalk.cyan('elm.json')} file and a ${chalk.cyan('LintConfig.elm')} file in ${chalk.cyan(path.dirname(userElmJson))}.

I can help set you up with an initial configuration if you run ${chalk.cyan('elm-lint init')}.`
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
    return writeElmJsonFile(userSrc, elmLintSrc, elmJsonPath, elmJson);
  });
  return Promise.all([copyElmLintSrcJob, createElmJsonFile]);
}

function writeElmJsonFile(userSrc, elmLintSrc, elmJsonPath, elmJson) {
  const fsWriteFile = util.promisify(fs.writeFile);

  // Update source-directories in the project's elm.json
  elmJson['source-directories'] = elmJson['source-directories']
    .map(directory => path.resolve(userSrc, directory))
    .concat([path.resolve(elmLintSrc)]);

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
      ['./elm-lint-src/Elm/Lint/Main.elm'],
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
`An error occurred while compiling your configuration for \`elm-lint\`.
I need your configuration to compile in order to know how to analyze your files.
Hopefully the compiler error above will help you figure out how to fix it.

If you see an error about the use of ${chalk.yellow('Debug')}, then you likely
use it somewhere, which is not allowed by default.
You may want to run elm-lint with ${chalk.yellow('--debug')}.

If that is not the case, maybe you forgot to add some dependencies that contains
the rules you wished to enable?`
            ) /* eslint-enable prettier/prettier */
          )
        );
      }
    });
  });
}

module.exports = {build};

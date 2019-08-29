const path = require('path');
const util = require('util');
const chalk = require('chalk');
const fs = require('fs-extra');
const elmCompiler = require('node-elm-compiler');
const getElmBinary = require('./elm-binary');
const dependencies = require('./dependencies');

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
  const userSrc = path.join(projectToLint, args.config || 'lint');
  const userElmJson = path.join(userSrc, 'elm.json');

  // Destination directories
  const projectFolder = path.join(dest, 'project');
  const elmJsonPath = path.join(projectFolder, 'elm.json');
  const elmLintSrc = path.join(projectFolder, 'elm-lint-src');

  // Promisified functions
  const fsReadJson = util.promisify(fs.readJson);
  const fsCopy = util.promisify(fs.copy);
  const fsRemove = util.promisify(fs.remove);

  // Copy our code into the project folder
  // TODO Performance: Copy only the Elm files
  const copyElmLintSrcJob = fsCopy(templateSrc, elmLintSrc, {
    overwrite: true
  }).then(() =>
    // Delete the LintConfig that we use for development
    // TODO Performance: Don't copy LintConfig.elm in the first place
    fsRemove(path.join(elmLintSrc, 'LintConfig.elm'))
  );
  // Load lint project's elm.json file contents
  const copyUserProjectJob = Promise.all([
    fsReadJson(userElmJson).catch(error => {
      if (error.code === 'ENOENT') {
        return Promise.reject(
          new Error(
            `-${chalk.green(
              '-- INCORRECT CONFIGURATION -----------------------------------------------------'
            )}

I could not find a lint configuration. I was expecting to find an ${chalk.cyan(
              'elm.json'
            )} file and a ${chalk.cyan('LintConfig.elm')} file in ${chalk.cyan(
              path.dirname(userElmJson)
            )}.

I can help set you up with an initial configuration if you run ${chalk.cyan(
              'elm-lint init'
            )}.`
          )
        );
      }

      return Promise.reject(error);
    }),
    dependencies.get(userElmJson)
  ]).then(([elmJson, dependencies]) => {
    elmJson.dependencies = dependencies;
    // Copy the user code into the project folder
    const sourceDirectoryCopyJobs = elmJson['source-directories']
      .filter(directory => directory === '.' || directory.startsWith('./'))
      .map(directory =>
        // TODO Performance: Copy only the Elm files
        fsCopy(
          path.join(userSrc, directory),
          path.join(projectFolder, directory),
          {
            overwrite: true
          }
        )
      );
    return Promise.all(sourceDirectoryCopyJobs).then(() =>
      // TODO Performance: Run writeElmJsonFile in parallel of sourceDirectoryCopyJobs
      // It requires copying only the Elm files, otherwise the elm.json file might get overwritten.
      writeElmJsonFile(userSrc, elmLintSrc, elmJsonPath, elmJson)
    );
  });
  return Promise.all([copyElmLintSrcJob, copyUserProjectJob]);
}

function writeElmJsonFile(userSrc, elmLintSrc, elmJsonPath, elmJson) {
  const fsWriteFile = util.promisify(fs.writeFile);

  // Update source-directories and dependencies in the project's elm.json
  const sourceDirectories = elmJson['source-directories'].map(directory => {
    // If the source-directory is in the project, then leave as is
    if (directory === '.' || directory.startsWith('./')) {
      return directory;
    }

    // If not, files in the directory will end up not being included in the
    // project, and the build will fail.
    return path.resolve(userSrc, directory);
  });
  elmJson['source-directories'] = sourceDirectories.concat([elmLintSrc]);

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
          new Error(`
${chalk.green(
  '-- INCORRECT CONFIGURATION -----------------------------------------------------'
)}

An error occurred while compiling your configuration for \`elm-lint\`.
I need your configuration to compile in order to know how to analyze your files.
Hopefully the compiler error above will help you figure out how to fix it.

Hint: Maybe you forgot to add some dependencies that contains the rules you
wished to enable?
`)
        );
      }
    });
  });
}

module.exports = {build};

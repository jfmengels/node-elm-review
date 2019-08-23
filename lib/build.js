const path = require('path');
const chalk = require('chalk');
const fs = require('fs-extra');
const elmCompiler = require('node-elm-compiler');
const getElmBinary = require('./elm-binary');
const getDependencies = require('./get-dependencies');

async function build(args, packageJson) {
  const generatedCodeDir = path.join(
    '.',
    'elm-stuff',
    'generated-code',
    'jfmengels',
    'elm-lint',
    packageJson.version
  );
  const dest = path.join(process.cwd(), generatedCodeDir);
  const binaryPath = path.resolve(dest, 'main.js');
  createTemplateProject(args, dest);
  await compileElmProject(args, dest, binaryPath);
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

function createTemplateProject(args, dest) {
  // Source directories
  const templateSrc = path.join(__dirname, '../template/src');
  const userSrc = path.join(process.cwd(), args['lint-folder'] || 'lint');
  const userElmJson = path.join(userSrc, 'elm.json');
  // Destination directories
  const projectFolder = path.join(dest, 'project');
  const elmJsonPath = path.join(projectFolder, 'elm.json');
  const elmLintSrc = path.join(projectFolder, 'elm-lint-src');

  // Lint project's elm.json file contents
  const elmJson = fs.readJsonSync(userElmJson);

  // Copy our code into the project folder
  fs.copySync(templateSrc, elmLintSrc, {
    overwrite: true
  });

  // Delete the LintConfig that we use for development
  fs.removeSync(path.join(elmLintSrc, 'LintConfig.elm'));
  // Copy the user code into the project folder
  elmJson['source-directories']
    .filter(directory => directory === '.' || directory.startsWith('./'))
    .forEach(directory => {
      // TODO Performance: Run all of these in parallel
      fs.copySync(
        path.join(userSrc, directory),
        path.join(projectFolder, directory),
        {
          overwrite: true
        }
      );
    });

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
  elmJson['source-directories'] = sourceDirectories.concat([
    elmLintSrc,
    // TODO Remove once elm-lint and elm-lint-reporter are published
    path.resolve(__dirname, '../../elm-lint/src'),
    path.resolve(__dirname, '../../elm-lint-reporter/src')
  ]);
  elmJson.dependencies = getDependencies(elmJsonPath);
  fs.writeFileSync(elmJsonPath, JSON.stringify(elmJson, null, 4));
}

function compileElmProject(args, dest, binaryPath) {
  const compileOptions = {
    cwd: path.join(dest, 'project'),
    output: binaryPath,
    debug: Boolean(args.debug),
    optimize: !args.debug,
    verbose: false,
    warn: false,
    pathToElm: getElmBinary(args),
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

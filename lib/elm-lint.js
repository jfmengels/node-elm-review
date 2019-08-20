// @flow
/* eslint-disable unicorn/no-process-exit */

process.title = 'elm-lint';

function errorHandler(err) {
  console.error(err.message || err);
  process.exit(1);
}

process.on('uncaughtException', errorHandler);

const path = require('path');
const chalk = require('chalk');
const which = require('which');
const fs = require('fs-extra');
const minimist = require('minimist');
const elmCompiler = require('node-elm-compiler');
const packageJson = require('../package.json');
const init = require('./init');
const install = require('./install');
const runLinting = require('./runner');
const elmFiles = require('./elm-files');

const generatedCodeDir = path.join(
  '.',
  'elm-stuff',
  'generated-code',
  'jfmengels',
  'elm-lint',
  'custom-binary'
);

const args = minimist(process.argv.slice(2), {
  alias: {
    help: 'h'
  },
  boolean: ['warn', 'version', 'help', 'debug']
});

function printUsage(str) {
  console.log(`Usage: ${process.title} ${str}\n`);
}

if (args.help) {
  [
    init.description,
    `[FILES] # Run linting on given files. Default is '${elmFiles.defaultGlob}' (TO BE IMPLEMENTED)`,
    '[--compiler /path/to/compiler] # Run linting with given Elm compiler',
    '[--fix] # Automatically fix some of the errors, pending your approval',
    '[--version] # Print version string and exit',
    '[--debug] # Run in an non-optimized Elm program. This can allow you to have Debug statements in your configuration or rules',
    '[--no-color] # Disable coloring in the output',
    install.description
  ].forEach(printUsage);

  process.exit(1);
}

if (args.version) {
  console.log(packageJson.version);
  process.exit(0);
}

if (args._[0] === 'init') {
  init.initializeProject();
  process.exit(0);
}

let pathToElmBinary;

if (args.compiler === undefined) {
  try {
    pathToElmBinary = which.sync('elm');
  } catch (error) {
    throw new Error(
      `Cannot find elm executable, make sure it is installed.
(If elm is not on your path or is called something different the --compiler flag might help.)`
    );
  }
} else {
  try {
    pathToElmBinary = which.sync(path.resolve(args.compiler));
  } catch (error) {
    throw new Error(
      'The --compiler option must be given a path to an elm executable.'
    );
  }
}

if (args._[0] === 'install') {
  if (args._.length === 1) {
    console.error(`
${chalk.green(
  '-- INSTALL WHAT? ---------------------------------------------------------------'
)}

I am expecting commands like:

    elm-lint install elm/http
    elm-lint install elm/json
    elm-lint install elm/random

I am missing a package name.`);
    process.exit(1);
  }

  if (args._.length > 2) {
    console.error(`
${chalk.green(
  '-- INSTALL WHAT? ---------------------------------------------------------------'
)}

I am expecting commands like:

    elm-lint install elm/http
    elm-lint install elm/json
    elm-lint install elm/random

I can only install one package at a time, but I got several. Try removing the
arguments after \`install\` until you only have one left.`);
    process.exit(1);
  }

  install.installDependency(pathToElmBinary, args._[1]);
  process.exit(0);
}

function createTemplateProject(dest) {
  const templateSrc = path.join(__dirname, '../template');
  fs.removeSync(path.join(templateSrc, 'elm-stuff'));
  fs.copySync(templateSrc, dest, {overwrite: true});
  try {
    fs.copySync(
      path.join(process.cwd(), 'LintConfig.elm'),
      path.join(dest, 'src/LintConfig.elm'),
      {
        overwrite: true
      }
    );
  } catch (error) {
    console.error(`
${chalk.green(
  '-- CONFIGURATION NOT FOUND -----------------------------------------------------'
)}

I could not find a LintConfig.elm file.
I need it in order to know how to analyze your files.

Hint: You can create one by using the \`init\` sub-command, like

  elm-lint init
`);
    process.exit(1);
  }

  const elmJsonPath = path.join(dest, 'elm.json');
  const pkg = fs.readJsonSync(elmJsonPath);
  fs.writeFileSync(elmJsonPath, JSON.stringify(pkg, null, 4));
}

function compileElmProjectSync(dest, binary) {
  const compileOptions = {
    cwd: dest,
    output: binary,
    optimize: !args.debug,
    verbose: false,
    warn: false,
    pathToElm: pathToElmBinary,
    processOpts: {
      env: process.env,
      stdio: ['ignore', 'ignore', process.stderr]
    }
  };

  return new Promise((resolve, reject) => {
    const compileProcess = elmCompiler.compile(
      ['src/Main.elm'],
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

async function initializeProject(dest, binary) {
  createTemplateProject(dest);
  await compileElmProjectSync(dest, binary);
  const oldConsoleWarn = console.warn;
  // $FlowFixMe
  console.warn = function(...args) {
    if (args.length === 1 && args[0].indexOf('Compiled in DEV mode') === 0)
      return;
    return oldConsoleWarn.apply(console, args);
  };

  // $FlowFixMe
  const Elm = require(path.join(dest, './main'));
  return runLinting(args, Elm);
}

function runElmLint() {
  const dest = path.join(process.cwd(), generatedCodeDir);
  const binary = path.resolve(dest, 'main.js');
  return initializeProject(dest, binary);
}

module.exports = () => {
  try {
    runElmLint().catch(errorHandler);
  } catch (error) {
    errorHandler(error);
  }
};

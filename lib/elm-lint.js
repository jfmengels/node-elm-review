// @flow

process.title = 'elm-lint';

function errorHandler(err) {
  console.error(err.message || err); // eslint-disable-line no-console
  process.exit(1);
}

process.on('uncaughtException', errorHandler);

const path = require('path');
const chalk = require('chalk')
const fs = require('fs-extra');
const minimist = require('minimist');
const elmCompiler = require('node-elm-compiler');
const init = require('./init')
const runLinting = require('./runner')

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
    help: 'h',
  },
  boolean: ['warn', 'version', 'help']
});

const defaultGlob = '**/*.elm';

function printUsage(str) {
  console.log(`Usage: ${process.title} ${str}\n`); // eslint-disable-line no-console
}

if (args.help) {
  [
    init.description,
    `[FILES] # Run linting on given files. Default is '${defaultGlob}' (TO BE IMPLEMENTED)`,
    '[--compiler /path/to/compiler] # Run linting with given Elm compiler',
    '[--version] # Print version string and exit',
  ].forEach(printUsage);

  process.exit(1);
}

if (args.version) {
  console.log(require('../package.json').version); // eslint-disable-line no-console
  process.exit(0);
}

if (args._[0] == 'init') {
  init.initializeProject()
  process.exit(0);
}

function createTemplateProject(dest) {
  const templateSrc = path.join(__dirname, '../template');
  fs.copySync(templateSrc, dest, {overwrite: true});
  try {
    fs.copySync(path.join(process.cwd(), 'LintConfig.elm'), path.join(dest, 'src/LintConfig.elm'), {
      overwrite: true
    });
  } catch (err) {
    console.error(`
${chalk.green("-- CONFIGURATION NOT FOUND -----------------------------------------------------")}

I could not find a LintConfig.elm file.
I need it in order to know how to analyze your files.

Hint: You can create one by using the \`init\` sub-command, like

  elm-lint init
`)
    process.exit(1);
  }

  const elmJsonPath = path.join(dest, 'elm.json');
  const pkg = fs.readJsonSync(elmJsonPath);
  pkg['source-directories'] = pkg['source-directories'].concat(
    path.relative(dest, process.cwd()) + '/src'
  );
  fs.writeFileSync(elmJsonPath, JSON.stringify(pkg, null, 4));
}

function compileElmProjectSync(dest, binary) {
  const compileOptions = {
    cwd: dest,
    output: binary,
    verbose: false,
    warn: false,
    processOpts: {
      env: process.env,
      stdio: ['ignore', 'ignore', process.stderr]
    }
  };

  return new Promise((resolve, reject) => {
    const compileProcess = elmCompiler.compile(['src/LintApp.elm'], compileOptions)

    compileProcess.on('close', function(exitCode) {
      if (exitCode === 0) {
        resolve();
      } else {
        reject(`
${chalk.green("-- INCORRECT CONFIGURATION -----------------------------------------------------")}

An error occurred while compiling your configuration for \`elm-lint\`.
I need your configuration to compile in order to know how to analyze your files.
Hopefully the compiler error above will help you figure out how to fix it.

Hint: Maybe you forgot to add some dependencies that contains the rules you
wished to enable?
`);
      }
    });
  });
}

function initializeProject(dest, binary) {
  createTemplateProject(dest);
  return compileElmProjectSync(dest, binary).then(() => {
    const oldConsoleWarn = console.warn
    console.warn = function () {
      if (arguments.length === 1 && arguments[0].indexOf('Compiled in DEV mode') === 0) return
      return oldConsoleWarn.apply(console, arguments)
    }
    const Elm = require(path.join(dest, './compiledLintApp'));
    runLinting(args, Elm)
  })
}

function runElmLint() {
  const dest = path.join(process.cwd(), generatedCodeDir);
  const binary = path.resolve(dest, 'compiledLintApp.js');
  return initializeProject(dest, binary);
}

module.exports = () => {
  try {
    runElmLint().catch(errorHandler)
  } catch (err) {
    errorHandler(err);
  }
};

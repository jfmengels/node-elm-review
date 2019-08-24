// @flow
/* eslint-disable unicorn/no-process-exit */

process.title = 'elm-lint';

process.on('uncaughtException', errorHandler);

const minimist = require('minimist');
const packageJson = require('../package.json');
const init = require('./init');
const builder = require('./build');
const runLinting = require('./runner');
const elmFiles = require('./elm-files');

const args = minimist(process.argv.slice(2), {
  alias: {
    help: 'h'
  },
  boolean: ['warn', 'version', 'help', 'debug']
});

function printUsage(str) {
  console.log(`Usage: ${process.title} ${str}\n`);
}

function errorHandler(err) {
  if (args.debug) {
    console.error(err);
  } else {
    console.error(err.message || err);
  }

  process.exit(1);
}

if (args.help) {
  [
    init.description,
    '[--project /path/to/project/to/lint] # Lint the given project instead of the project of the current directory',
    '[--lint-folder /path/to/your/lint/folder] # Run linting with the configuration defined in the given folder',
    '[--compiler /path/to/compiler] # Run linting with given Elm compiler',
    '[--elm-format-path /path/to/elm-format] # Specify the path to `elm-format`, used when fixing errors automatically',
    '[--fix] # Automatically fix some of the errors, pending your approval',
    '[--version] # Print version string and exit',
    '[--debug] # Run in an non-optimized Elm program. This can allow you to have Debug statements in your configuration or rules',
    '[--no-color] # Disable coloring in the output'
  ].forEach(printUsage);

  process.exit(0);
}

if (args.version) {
  console.log(packageJson.version);
  process.exit(0);
}

if (args._[0] === 'init') {
  init
    .initializeProject(args)
    .then(() => {
      process.exit(0);
    })
    .catch(errorHandler);
}

async function runElmLint() {
  const elmModule = await builder.build(args, packageJson);
  return runLinting(args, elmModule);
}

module.exports = () => {
  try {
    runElmLint().catch(errorHandler);
  } catch (error) {
    errorHandler(error);
  }
};

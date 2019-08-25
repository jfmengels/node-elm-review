// @flow
/* eslint-disable unicorn/no-process-exit */

process.title = 'elm-lint';

const minimist = require('minimist');
const packageJson = require('../package.json');
const help = require('./help');
const init = require('./init');
const builder = require('./build');
const runLinting = require('./runner');
const elmFiles = require('./elm-files');

const args = minimist(process.argv.slice(2), {
  alias: {
    help: 'h',
    version: 'v'
  },
  boolean: ['warn', 'version', 'help', 'debug']
});

process.on('uncaughtException', errorHandler);
function errorHandler(err) {
  if (args.debug) {
    console.error(err);
  } else {
    console.error(err.message || err);
  }

  process.exit(1);
}

async function runElmLint() {
  const projectToLint = elmFiles.getProjectToLint(args);
  const elmModule = await builder.build(args, packageJson, projectToLint);
  return runLinting(args, elmModule, projectToLint);
}

module.exports = () => {
  if (args.version) {
    console.log(packageJson.version);
    return;
  }

  if (args.help) {
    return help();
  }

  if (args._[0] === 'init') {
    return init.initializeProject(args).catch(errorHandler);
  }

  runElmLint().catch(errorHandler);
};

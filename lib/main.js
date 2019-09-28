// @flow
/* eslint-disable unicorn/no-process-exit */

process.title = 'elm-review';

const minimist = require('minimist');
const packageJson = require('../package.json');
const help = require('./help');
const initializeProject = require('./init');
const builder = require('./build');
const runReview = require('./runner');
const elmFiles = require('./elm-files');

const args = minimist(process.argv.slice(2), {
  alias: {
    help: 'h',
    version: 'v'
  },
  boolean: ['version', 'help', 'debug']
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

async function runElmReview() {
  const projectToReview = elmFiles.getProjectToReview(args);
  const elmModule = await builder.build(args, packageJson, projectToReview);
  return runReview(args, elmModule, projectToReview);
}

module.exports = () => {
  if (args.version) {
    console.log(packageJson.version);
    return;
  }

  if (args._[0] === 'init') {
    if (args.help) {
      return help.init();
    }

    return initializeProject(args).catch(errorHandler);
  }

  if (args.help) {
    return help.review(packageJson);
  }

  runElmReview().catch(errorHandler);
};

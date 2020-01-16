// @flow
/* eslint-disable unicorn/no-process-exit */

process.title = 'elm-review';

const help = require('./help');
const initializeProject = require('./init');
const builder = require('./build');
const runReview = require('./runner');
const Options = require('./options');

const options = Options.compute(process.argv);

process.on('uncaughtException', errorHandler);
function errorHandler(err) {
  if (options.debug) {
    console.error(err);
  } else {
    console.error(err.message || err);
  }

  process.exit(1);
}

async function runElmReview() {
  const elmModule = await builder.build(options);
  return runReview(options, elmModule);
}

module.exports = () => {
  if (options.version) {
    console.log(options.packageJsonVersion);
    return;
  }

  if (options.subcommand === 'init') {
    if (options.help) {
      return help.init();
    }

    return initializeProject(options).catch(errorHandler);
  }

  if (options.help) {
    return help.review(options);
  }

  runElmReview().catch(errorHandler);
};

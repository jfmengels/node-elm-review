// @flow
/* eslint-disable unicorn/no-process-exit */

process.title = 'elm-review';

const help = require('./help');
const initializeProject = require('./init');
const builder = require('./build');
const runner = require('./runner');
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
  const app = await runner.initializeApp(options, elmModule).catch(errorHandler);
  const success = await runner.runReview(options, app).catch(errorHandler);
  process.exit(success ? 0 : 1);
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

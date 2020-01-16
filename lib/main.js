// @flow
/* eslint-disable unicorn/no-process-exit */

process.title = 'elm-review';

const help = require('./help');
const initializeProject = require('./init');
const watch = require('./watch');
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
  const {elmModule} = await builder.build(options);
  const {app} = await runner.initializeApp(options, elmModule);
  const success = await runner.runReview(options, app);
  process.exit(success ? 0 : 1);
}

async function runElmReviewInWatchMode() {
  const {elmModule, reviewElmJson, reviewElmJsonPath} = await builder.build(options);
  const initialization = await runner.initializeApp(options, elmModule);
  watch(options, {...initialization, reviewElmJson, reviewElmJsonPath}, errorHandler);
  await runner.runReview(options, initialization.app).catch(errorHandler);
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

  if (options.watch) {
    return runElmReviewInWatchMode().catch(errorHandler);
  }

  runElmReview().catch(errorHandler);
};

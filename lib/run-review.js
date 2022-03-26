const path = require('path');
const chalk = require('chalk');
const report = require('./report');
const AppState = require('./state');
const Benchmark = require('./benchmark');
const promisifyPort = require('./promisify-port');
const SuppressedErrors = require('./suppressed-errors');

module.exports = {
  runReview,
  startReview,
  requestReview
};

async function runReview(options, app) {
  if (options.watch) {
    startReview(options, app);
    return undefined;
  }

  if (options.subcommand === 'suppress') {
    Benchmark.start(options, 'review');
    const result = await promisifyPort({
      subscribeTo: app.ports.suppressionsResponse,
      sendThrough: app.ports.startGeneratingSuppressions,
      data: null
    });
    Benchmark.end(options, 'review');
    await SuppressedErrors.write(options, result);

    if (options.report !== 'json') {
      const orange = chalk.keyword('orange');
      console.log(
        `I created suppressions files in ${orange(
          path.relative(process.cwd(), options.suppressedErrorsFolder())
        )}`
      );
    }

    return true;
  }

  Benchmark.start(options, 'review');
  const result = await promisifyPort({
    subscribeTo: app.ports.reviewReport,
    sendThrough: app.ports.startReview,
    data: null
  });
  Benchmark.end(options, 'review');

  if (result.suppressedErrors) {
    await SuppressedErrors.write(options, result.suppressedErrors);
  }

  if (result.errors.length > 0) {
    await report(options, result);
  } else if (Object.keys(result.extracts).length > 0) {
    // TODO
    console.log(JSON.stringify(result.extracts, 0, 4));
  }

  return result.success;
}

let isVeryFirstRun = true;
function startReview(options, app) {
  if (options.report !== 'json' && !isVeryFirstRun) {
    console.log('Running...');
  }

  isVeryFirstRun = false;
  return app.ports.startReview.send(null);
}

function requestReview(options, app) {
  if (AppState.requestReview()) {
    startReview(options, app);
  }
}

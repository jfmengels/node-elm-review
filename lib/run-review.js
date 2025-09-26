/**
 * @import {Options} from './types/options';
 * @import {ReviewApp} from './types/app';
 */

const path = require('node:path');
const chalk = require('chalk');
const Benchmark = require('./benchmark');
const promisifyPort = require('./promisify-port');
const Report = require('./report');
const AppState = require('./state');
const SuppressedErrors = require('./suppressed-errors');

/**
 * @param {Options} options
 * @param {ReviewApp} app
 * @returns {Promise<boolean>}
 */
async function runReview(options, app) {
  if (options.watch) {
    startReview(options, app);
    return false;
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
          path.relative(options.cwd, options.suppressedErrorsFolder())
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

  await Report.report(options, result);

  return result.success;
}

let isVeryFirstRun = true;

/**
 * @param {Options} options
 * @param {ReviewApp} app
 * @returns {void}
 */
function startReview(options, app) {
  if (options.report !== 'json' && !isVeryFirstRun) {
    console.log('Running...');
  }

  isVeryFirstRun = false;
  app.ports.startReview.send(null);
}

/**
 * @param {Options} options
 * @param {ReviewApp} app
 * @returns {void}
 */
function requestReview(options, app) {
  if (AppState.requestReview()) {
    startReview(options, app);
  }
}

module.exports = {
  runReview,
  startReview,
  requestReview
};

const path = require('path');
const chalk = require('chalk');
const Report = require('./report');
const AppState = require('./state');
const Benchmark = require('./benchmark');
const promisifyPort = require('./promisify-port');
const SuppressedErrors = require('./suppressed-errors');

/**
 * @typedef { import("./types/options").Options } Options
 * @typedef { import("./types/app").App } App
 * @typedef { import("./types/app").FileReceipt } FileReceipt
 * @typedef { import("./types/content").ElmFile } ElmFile
 * @typedef { import("./types/content").Readme } Readme
 * @typedef { import("./types/content").ElmJsonData } ElmJsonData
 * @typedef { import("./types/content").Dependencies } Dependencies
 * @typedef { import("./types/content").LinksToRuleDocs } LinksToRuleDocs
 */

module.exports = {
  runReview,
  startReview,
  requestReview
};

/**
 * @param {Options} options
 * @param {App} app
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

  await Report.report(options, result);

  return result.success;
}

let isVeryFirstRun = true;

/**
 * @param {Options} options
 * @param {App} app
 */
function startReview(options, app) {
  if (options.report !== 'json' && !isVeryFirstRun) {
    console.log('Running...');
  }

  isVeryFirstRun = false;
  return app.ports.startReview.send(null);
}

/**
 * @param {Options} options
 * @param {App} app
 */
function requestReview(options, app) {
  if (AppState.requestReview()) {
    startReview(options, app);
  }
}

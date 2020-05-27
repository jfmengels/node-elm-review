// @flow
/* eslint-disable unicorn/no-process-exit */

process.title = 'elm-review';

const path = require('path');
const help = require('./help');
const initializeProject = require('./init');
const watch = require('./watch');
const builder = require('./build');
const runner = require('./runner');
const appState = require('./state');
const appWrapper = require('./app-wrapper');
const errorMessage = require('./error-message');

const options = appState.getOptions();

process.on('uncaughtException', errorHandler);
process.on('unhandledRejection', errorHandler);

function errorHandler(err) {
  let userSrc = null;
  try {
    userSrc = options.userSrc();
  } catch (_) {
    userSrc = process.cwd();
  }

  const reviewElmJsonPath = path.join(userSrc, 'elm.json');

  if (err instanceof errorMessage.CustomError) {
    console.error(errorMessage.report(options, err, reviewElmJsonPath));
  } else {
    console.error(reportUnknownError(err, reviewElmJsonPath));
  }

  process.exit(1);
}

function reportUnknownError(err, reviewElmJsonPath) {
  if (options.report === 'json') {
    const json = {
      title: 'UNEXPECTED ERROR',
      path: reviewElmJsonPath,
      error: err.message || err
    };
    if (options.debug) {
      return JSON.stringify(json, null, 2);
    }

    return JSON.stringify(json);
  }

  if (options.debug) {
    return err;
  }

  return err.message || err;
}

async function runElmReview() {
  const {elmModulePath} = await builder.build(options);
  const {app} = await runner.initializeApp(options, elmModulePath);
  const success = await runner.runReview(options, app);
  appState.exitRequested(success ? 0 : 1);
}

async function runElmReviewInWatchMode() {
  appWrapper.stop();
  const {elmModulePath, reviewElmJson, reviewElmJsonPath} = await builder.build(
    options
  );
  const initialization = await runner.initializeApp(options, elmModulePath);
  watch(
    options,
    {...initialization, reviewElmJson, reviewElmJsonPath},
    runElmReviewInWatchMode,
    errorHandler
  );
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

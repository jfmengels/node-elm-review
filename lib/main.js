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
const Options = require('./options');
const appWrapper = require('./app-wrapper');
const errorMessage = require('./error-message');

const options = Options.compute(process.argv);

process.on('uncaughtException', errorHandler);
process.on('unhandledRejection', errorHandler);

function errorHandler(err) {
  const parsedError = parse(err.message);
  let userSrc = null;
  try {
    userSrc = options.userSrc();
  } catch (_) {}

  const reviewElmJsonPath = path.join(userSrc || process.cwd(), 'elm.json');

  if (parsedError && parsedError.customElmReviewError) {
    reportCustomError(parsedError, reviewElmJsonPath);
  } else {
    reportUnknownError(err, reviewElmJsonPath);
  }

  process.exit(1);
}

function reportCustomError(err, reviewElmJsonPath) {
  if (options.report === 'json') {
    if (options.debug) {
      console.error(
        JSON.stringify(errorMessage.formatJson(err, reviewElmJsonPath), 0, 2)
      );
    } else {
      console.error(
        JSON.stringify(errorMessage.formatJson(err, reviewElmJsonPath))
      );
    }
  } else if (options.debug) {
    console.error(errorMessage.formatHuman(err));
  } else {
    console.error(errorMessage.formatHuman(err));
  }
}

function reportUnknownError(err, reviewElmJsonPath) {
  if (options.report === 'json') {
    const json = {
      title: 'UNEXPECTED ERROR',
      path: reviewElmJsonPath,
      error: err.message || err
    };
    if (options.debug) {
      console.error(JSON.stringify(json, 0, 2));
    } else {
      console.error(JSON.stringify(json));
    }
  } else if (options.debug) {
    console.error(err);
  } else {
    console.error(err.message || err);
  }
}

function parse(err) {
  try {
    return JSON.parse(err);
  } catch (_) {
    return null;
  }
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

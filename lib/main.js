// @flow
/* eslint-disable unicorn/no-process-exit */

process.title = 'elm-review';

const path = require('path');
const temp = require('temp');
const help = require('./help');
const init = require('./init');
const builder = require('./build');
const runner = require('./runner');
const appState = require('./state');
const newRule = require('./new-rule');
const Anonymize = require('./anonymize');
const newPackage = require('./new-package');
const appWrapper = require('./app-wrapper');
const errorMessage = require('./error-message');
const {watchFiles, watchConfiguration} = require('./watch');

const options = appState.getOptions();

process.on('uncaughtException', errorHandler);
process.on('unhandledRejection', errorHandler);

function errorHandler(err) {
  temp.cleanupSync();
  let userSrc = null;
  try {
    userSrc = options.userSrc();
  } catch (_) {
    userSrc = process.cwd();
  }

  const reviewElmJsonPath = path.join(userSrc, 'elm.json');

  const errorToReport =
    err instanceof errorMessage.CustomError
      ? err
      : errorMessage.unexpectedError(err);
  console.log(errorMessage.report(options, errorToReport, reviewElmJsonPath));

  process.exit(1);
}

async function runElmReview() {
  const {elmModulePath, reviewElmJson} = await builder.build(options);

  if (!elmModulePath) {
    appState.exitRequested(1);
    return;
  }

  const {app} = await runner.initializeApp(
    options,
    elmModulePath,
    reviewElmJson
  );
  const success = await runner.runReview(options, app);
  appState.exitRequested(success ? 0 : 1);
}

async function runElmReviewInWatchMode() {
  appWrapper.stop();
  const {elmModulePath, reviewElmJson, reviewElmJsonPath} = await builder.build(
    options
  );

  if (!elmModulePath) {
    watchConfiguration(
      options,
      {reviewElmJson, reviewElmJsonPath},
      () => {
        appState.buildRestarted();
        runElmReviewInWatchMode();
      },
      errorHandler
    );
    return;
  }

  const initialization = await runner.initializeApp(
    options,
    elmModulePath,
    reviewElmJson
  );
  watchFiles(
    options,
    {...initialization, reviewElmJson, reviewElmJsonPath},
    () => {
      appState.buildRestarted();
      runElmReviewInWatchMode();
    },
    errorHandler
  );
  await runner.runReview(options, initialization.app).catch(errorHandler);
}

module.exports = () => {
  if (options.version) {
    console.log(Anonymize.version(options));
    return;
  }

  if (options.subcommand === 'init') {
    if (options.help) {
      return help.init();
    }

    return init.promptAndCreate(options).catch(errorHandler);
  }

  if (options.subcommand === 'new-rule') {
    if (options.help) {
      return help.newRule();
    }

    return newRule.create(options).catch(errorHandler);
  }

  if (options.subcommand === 'new-package') {
    if (options.help) {
      return help.newPackage();
    }

    return newPackage(options).catch(errorHandler);
  }

  if (options.help) {
    return help.review(options);
  }

  if (options.watch) {
    return runElmReviewInWatchMode().catch(errorHandler);
  }

  runElmReview().catch(errorHandler);
};

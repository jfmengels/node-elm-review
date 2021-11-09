// @flow
/* eslint-disable unicorn/no-process-exit */

process.title = 'elm-review';

const path = require('path');
const temp = require('temp');
const Help = require('./help');
const Init = require('./init');
const Builder = require('./build');
const Runner = require('./runner');
const AppState = require('./state');
const Spinner = require('./spinner');
const NewRule = require('./new-rule');
const Anonymize = require('./anonymize');
const newPackage = require('./new-package');
const AppWrapper = require('./app-wrapper');
const ErrorMessage = require('./error-message');
const SuppressedErrors = require('./suppressed-errors');
const Watch = require('./watch');

const options = AppState.getOptions();

process.on('uncaughtException', errorHandler);
process.on('unhandledRejection', errorHandler);

function errorHandler(err) {
  Spinner.fail(undefined);
  temp.cleanupSync();
  let userSrc = null;
  try {
    userSrc = options.userSrc();
  } catch {
    userSrc = process.cwd();
  }

  const reviewElmJsonPath = path.join(userSrc, 'elm.json');

  const errorToReport =
    err instanceof ErrorMessage.CustomError
      ? err
      : ErrorMessage.unexpectedError(err);
  console.log(ErrorMessage.report(options, errorToReport, reviewElmJsonPath));

  process.exit(1);
}

async function runElmReview() {
  const {elmModulePath, reviewElmJson} = await Builder.build(options);
  await Builder.buildElmParser(options, reviewElmJson);

  if (!elmModulePath) {
    AppState.exitRequested(1);
    return;
  }

  const {app} = await Runner.initializeApp(
    options,
    elmModulePath,
    reviewElmJson
  );
  const success = await Runner.runReview(options, app);
  AppState.exitRequested(success ? 0 : 1);
}

async function runElmReviewInWatchMode() {
  AppWrapper.stop();
  const {elmModulePath, reviewElmJson, reviewElmJsonPath} = await Builder.build(
    options
  );
  await Builder.buildElmParser(options, reviewElmJson);

  if (!elmModulePath) {
    Watch.watchConfiguration(
      options,
      {reviewElmJson, reviewElmJsonPath},
      () => {
        AppState.buildRestarted();
        runElmReviewInWatchMode();
      },
      errorHandler
    );
    return;
  }

  const initialization = await Runner.initializeApp(
    options,
    elmModulePath,
    reviewElmJson
  );
  Watch.watchFiles(
    options,
    {...initialization, reviewElmJson, reviewElmJsonPath},
    () => {
      AppState.buildRestarted();
      runElmReviewInWatchMode();
    },
    errorHandler
  );
  await Runner.runReview(options, initialization.app).catch(errorHandler);
}

module.exports = () => {
  if (options.version) {
    console.log(Anonymize.version(options));
    return;
  }

  if (options.subcommand === 'init') {
    if (options.help) {
      return Help.init();
    }

    return Init.promptAndCreate(options).catch(errorHandler);
  }

  if (options.subcommand === 'new-rule') {
    if (options.help) {
      return Help.newRule();
    }

    return NewRule.create(options).catch(errorHandler);
  }

  if (options.subcommand === 'new-package') {
    if (options.help) {
      return Help.newPackage();
    }

    return newPackage(options).catch(errorHandler);
  }

  if (options.subcommand === 'suppress') {
    if (options.help) {
      return Help.suppress(options);
    }

    if (options.suppressCheckAfterTests) {
      return SuppressedErrors.checkForUncommittedSuppressions(options);
    }
  }

  if (options.help) {
    return Help.review(options);
  }

  if (options.watch) {
    return runElmReviewInWatchMode().catch(errorHandler);
  }

  runElmReview().catch(errorHandler);
};

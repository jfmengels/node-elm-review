process.title = 'elm-review';

if (!process.argv.includes('--no-color')) {
  if (process.env.NO_COLOR !== undefined && process.env.NO_COLOR !== '') {
    process.argv.push('--no-color');
  } else {
    // Force `chalk` to add colors by default.
    process.argv.push('--color');
  }
}

const path = require('path');
const chalk = require('chalk');
const Help = require('./help');
const Init = require('./init');
const Builder = require('./build');
const Runner = require('./runner');
const AppState = require('./state');
const Spinner = require('./spinner');
const NewRule = require('./new-rule');
const Anonymize = require('./anonymize');
const NewPackage = require('./new-package');
const AppWrapper = require('./app-wrapper');
const ElmBinary = require('./elm-binary');
const ResultCache = require('./result-cache');
const ErrorMessage = require('./error-message');
const SuppressedErrors = require('./suppressed-errors');
const Watch = require('./watch');
const exit = require('../vendor/exit');

/**
 * @typedef { import("./types/options").Options } Options
 * @typedef { import("./types/options").ReviewOptions } ReviewOptions
 */

/**
 * @type {Options}
 */
const options = AppState.getOptions();

process.on('uncaughtException', errorHandler);
process.on('unhandledRejection', errorHandler);

function errorHandler(err) {
  Spinner.fail(undefined);
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

  exit(1);
}

async function runElmReview() {
  const {elmModulePath, reviewElmJson, appHash} = await Builder.build(options);

  if (!elmModulePath) {
    AppState.exitRequested(1);
    return;
  }

  const [{app}] = await Promise.all([
    Builder.buildElmParser(options, reviewElmJson).then(() =>
      Runner.initializeApp(options, elmModulePath, reviewElmJson, appHash)
    ),

    ResultCache.load(
      options,
      options.ignoredDirs(),
      options.ignoredFiles(),
      options.resultCachePath(appHash)
    )
  ]);

  const success = await Runner.runReview(options, app);
  AppState.exitRequested(success ? 0 : 1);
}

async function runElmReviewInWatchMode() {
  AppWrapper.stop();
  const {elmModulePath, reviewElmJson, reviewElmJsonPath, appHash} =
    await Builder.build(options);
  await Builder.buildElmParser(options, reviewElmJson);

  if (!elmModulePath) {
    Watch.watchConfiguration(
      /** @type {ReviewOptions} */ (options),
      reviewElmJson,
      reviewElmJsonPath,
      () => {
        AppState.buildRestarted();
        runElmReviewInWatchMode();
      }
    );
    return;
  }

  const initialization = await Runner.initializeApp(
    options,
    elmModulePath,
    reviewElmJson,
    appHash
  );
  Watch.watchFiles(
    /** @type {ReviewOptions} */ (options),
    {...initialization, reviewElmJson, reviewElmJsonPath},
    () => {
      AppState.buildRestarted();
      runElmReviewInWatchMode();
    },
    errorHandler
  );
  await Runner.runReview(options, initialization.app).catch(errorHandler);
}

async function prepareOffline() {
  const elmBinary = await ElmBinary.getElmBinary(options);
  await ElmBinary.downloadDependenciesOfElmJson(
    elmBinary,
    /** @type {ReviewOptions} */ (options).elmJsonPath
  );

  const {elmModulePath, reviewElmJson} = await Builder.build(options);

  if (!elmModulePath) {
    AppState.exitRequested(1);
    return;
  }

  await Builder.buildElmParser(options, reviewElmJson);

  console.log(`${chalk.greenBright(
    'elm-review'
  )} is now ready to be run ${chalk.cyan('--offline')}.

You will need to run ${chalk.yellow(
    'elm-review prepare-offline'
  )} to keep the offline mode working
if either your review configuration or your project's dependencies change.`);
  exit(0);
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

    return NewPackage.create(options).catch(errorHandler);
  }

  if (options.subcommand === 'suppress') {
    if (options.help) {
      return Help.suppress();
    }

    if (options.suppressCheckAfterTests) {
      return SuppressedErrors.checkForUncommittedSuppressions(options);
    }
  }

  if (options.subcommand === 'prepare-offline') {
    if (options.help) {
      return Help.prepareOffline();
    }

    return prepareOffline();
  }

  if (options.help) {
    return Help.review(options);
  }

  if (options.watch) {
    return runElmReviewInWatchMode().catch(errorHandler);
  }

  runElmReview().catch(errorHandler);
};

// TODO(@lishaduck): Create a `setup` function.
process.title = 'elm-review';

if (!process.argv.includes('--no-color')) {
  if (process.env.NO_COLOR !== undefined && process.env.NO_COLOR !== '') {
    process.argv.push('--no-color');
  } else {
    // Force `chalk` to add colors by default.
    process.argv.push('--color');
  }
}

/**
 * @import {Options, ReviewOptions} from './types/options';
 */
const path = require('node:path');
const chalk = require('chalk');
const exit = require('../vendor/exit');
const Anonymize = require('./anonymize');
const AppWrapper = require('./app-wrapper');
const Builder = require('./build');
const ElmBinary = require('./elm-binary');
const ErrorMessage = require('./error-message');
const Help = require('./help');
const Init = require('./init');
const NewPackage = require('./new-package');
const NewRule = require('./new-rule');
const ResultCache = require('./result-cache');
const Runner = require('./runner');
const Spinner = require('./spinner');
const AppState = require('./state');
const SuppressedErrors = require('./suppressed-errors');
const Watch = require('./watch');

/**
 * @type {Options}
 */
// TODO(@lishaduck): Centralize all calls to just this & move into main.
const options = AppState.getOptions();

// TODO(@lishaduck): Move to aforementioned `setup` function.
process.on('uncaughtException', errorHandler);
process.on('unhandledRejection', errorHandler);

/**
 * Exit the process with status code 1 after printing an error message.
 *
 * @param {Error} err - An error object.
 * @returns {never}
 */
function errorHandler(err) {
  Spinner.fail();
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

/**
 * @returns {Promise<void>}
 */
async function runElmReview() {
  const {elmModulePath, reviewElmJson, appHash} = await Builder.build(options);

  if (!elmModulePath) {
    AppState.exitRequested(1);
    return;
  }

  const [{app}] = await Promise.all([
    Builder.buildElmParser(options, reviewElmJson).then(async () => {
      return await Runner.initializeApp(
        options,
        elmModulePath,
        reviewElmJson,
        appHash
      );
    }),

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

/**
 * @returns {Promise<void | never>}
 */
async function runElmReviewInWatchMode() {
  AppWrapper.stop();
  const {elmModulePath, reviewElmJson, reviewElmJsonPath, appHash} =
    await Builder.build(options);
  await Builder.buildElmParser(options, reviewElmJson);

  if (!elmModulePath) {
    Watch.watchConfiguration(
      // @ts-expect-error(TS2345): `Options` aren't assignable to `ReviewOptions`.
      options,
      reviewElmJson,
      reviewElmJsonPath,
      () => {
        AppState.buildRestarted();
        void runElmReviewInWatchMode();
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
      void runElmReviewInWatchMode();
    },
    errorHandler
  );

  try {
    await Runner.runReview(options, initialization.app);
  } catch (error) {
    errorHandler(error);
  }
}

/**
 * @returns {Promise<void>}
 */
async function prepareOffline() {
  const elmBinary = await ElmBinary.getElmBinary(options);
  ElmBinary.downloadDependenciesOfElmJson(
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

/**
 * @returns {Promise<void | never>}
 */
async function main() {
  if (options.version) {
    console.log(Anonymize.version(options));
    return;
  }

  switch (options.subcommand) {
    case 'init': {
      if (options.help) {
        Help.init();
        return;
      }

      try {
        await Init.promptAndCreate(options);
        return;
      } catch (error) {
        errorHandler(error);
      }
    }

    case 'new-rule': {
      if (options.help) {
        Help.newRule();
        return;
      }

      try {
        await NewRule.create(/** @type {ReviewOptions} */ (options));
        return;
      } catch (error) {
        errorHandler(error);
      }
    }

    case 'new-package': {
      if (options.help) {
        Help.newPackage();
        return;
      }

      try {
        await NewPackage.create(/** @type {ReviewOptions} */ options);
        return;
      } catch (error) {
        errorHandler(error);
      }
    }

    case 'suppress': {
      if (options.help) {
        Help.suppress();
        return;
      }

      if (options.suppressCheckAfterTests) {
        SuppressedErrors.checkForUncommittedSuppressions(options);
        return;
      }

      break;
    }

    case 'prepare-offline': {
      if (options.help) {
        Help.prepareOffline();
        return;
      }

      await prepareOffline();
      return;
    }

    default: {
      if (options.help) {
        Help.review(options);
        return;
      }

      if (options.watch) {
        try {
          await runElmReviewInWatchMode();
          return;
        } catch (error) {
          errorHandler(error);
        }
      }
    }
  }

  try {
    await runElmReview();
  } catch (error) {
    errorHandler(error);
  }
}

module.exports = main;

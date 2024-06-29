process.title = 'elm-review';

if (!process.argv.includes('--no-color')) {
  if (process.env.NO_COLOR !== undefined && process.env.NO_COLOR !== '') {
    process.argv.push('--no-color');
  } else {
    // Force `chalk` to add colors by default.
    process.argv.push('--color');
  }
}

const path = require('node:path');
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
 * @import {Options, ReviewOptions} from "./types/options"
 */

/**
 * @type {Options}
 */
const options = AppState.getOptions();

process.on('uncaughtException', errorHandler);
process.on('unhandledRejection', errorHandler);

/**
 * Exit the process with status code 1 after printing an error message.
 *
 * @param {Error} err - An error object.
 * @returns {never}
 */
function errorHandler(err) {
  // eslint unicorn/no-useless-undefined: ["warn", {"checkArguments": false}] -- Bad TS type.
  // eslint-disable-next-line unicorn/no-useless-undefined -- Above doesn't work?
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

  try {
    await Runner.runReview(options, initialization.app);
  } catch (error) {
    errorHandler(error);
  }
}

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
        return Help.init();
      }

      try {
        return await Init.promptAndCreate(options);
      } catch (error) {
        errorHandler(error);
      }
    }

    case 'new-rule': {
      if (options.help) {
        return Help.newRule();
      }

      try {
        return await NewRule.create(/** @type {ReviewOptions} */ (options));
      } catch (error) {
        errorHandler(error);
      }
    }

    case 'new-package': {
      if (options.help) {
        return Help.newPackage();
      }

      try {
        return await NewPackage.create(/** @type {ReviewOptions} */ options);
      } catch (error) {
        errorHandler(error);
      }
    }

    case 'suppress': {
      if (options.help) {
        return Help.suppress();
      }

      if (options.suppressCheckAfterTests) {
        return SuppressedErrors.checkForUncommittedSuppressions(options);
      }

      break;
    }

    case 'prepare-offline': {
      if (options.help) {
        return Help.prepareOffline();
      }

      return await prepareOffline();
    }

    default: {
      if (options.help) {
        return Help.review(options);
      }

      if (options.watch) {
        try {
          return await runElmReviewInWatchMode();
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

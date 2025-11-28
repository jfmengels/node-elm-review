/**
 * @import {Options, ReviewOptions} from './types/options';
 */
const path = require('node:path');
const process = require('node:process');
const chalk = require('chalk');
const exit = require('../vendor/exit');
const Anonymize = require('./anonymize');
const AppWrapper = require('./app-wrapper');
const Builder = require('./build');
const ElmBinary = require('./elm-binary');
const {readElmJson} = require('./elm-files');
const ProjectDependencies = require('./project-dependencies');
const ErrorMessage = require('./error-message');
const Help = require('./help');
const Init = require('./init');
const NewPackage = require('./new-package');
const NewRule = require('./new-rule');
const Options_ = require('./options');
const ResultCache = require('./result-cache');
const Runner = require('./runner');
const Spinner = require('./spinner');
const AppState = require('./state');
const SuppressedErrors = require('./suppressed-errors');
const Watch = require('./watch');

/**
 * @param {NodeJS.Process} process
 * @typedef {(err: Error) => never} ErrorHandler
 */

function setup(process) {
  process.title = 'elm-review';

  if (!process.argv.includes('--no-color')) {
    if (process.env.NO_COLOR !== undefined && process.env.NO_COLOR !== '') {
      process.argv.push('--no-color');
    } else {
      // Force `chalk` to add colors by default.
      process.argv.push('--color');
    }
  }

  const cwd = process.cwd();
  if (process.env.ELM_HOME) {
    process.env.ELM_HOME = path.resolve(cwd, process.env.ELM_HOME);
  }

  const options = Options_.compute(process.argv, cwd);

  const errorHandler = errorHandlerFactory(options);

  process.on('uncaughtException', errorHandler);
  process.on('unhandledRejection', errorHandler);

  return {options, errorHandler};
}

/**
 * Exit the process with status code 1 after printing an error message.
 *
 * @param {Options} options - An error object.
 * @returns {ErrorHandler}
 */
function errorHandlerFactory(options) {
  return (err) => {
    Spinner.fail(undefined, options.report);

    let userSrc = null;
    try {
      userSrc = options.userSrc();
    } catch {
      userSrc = options.cwd;
    }

    const reviewElmJsonPath = path.join(userSrc, 'elm.json');

    const errorToReport =
      err instanceof ErrorMessage.CustomError
        ? err
        : ErrorMessage.unexpectedError(err);
    console.log(ErrorMessage.report(options, errorToReport, reviewElmJsonPath));

    exit(1);
  };
}

/**
 * @param {Options} options
 * @returns {Promise<void>}
 */
async function runElmReview(options) {
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
 * @param {Options} options
 * @param {ErrorHandler} errorHandler
 * @returns {Promise<void | never>}
 */
async function runElmReviewInWatchMode(options, errorHandler) {
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
        void runElmReviewInWatchMode(options, errorHandler);
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
      void runElmReviewInWatchMode(options, errorHandler);
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
 * @param {ReviewOptions} options
 * @returns {Promise<void>}
 */
async function prepareOffline(options) {
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

  const elmVersion = reviewElmJson['elm-version'];

  await Promise.all([
    Builder.buildElmParser(options, reviewElmJson),
    readElmJson(options).then((elmJson) =>
      ProjectDependencies.collect(options, JSON.parse(elmJson), elmVersion)
    )
  ]);

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
 * @returns {Promise<void>}
 */
async function main() {
  const {options, errorHandler} = setup(process);

  await app(options, errorHandler);
}

/**
 * @param {Options} options
 * @param {ErrorHandler} errorHandler
 * @returns {Promise<void>}
 */
async function app(options, errorHandler) {
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

      // @ts-expect-error(TS2345): `Options` aren't assignable to `ReviewOptions`.
      await prepareOffline(options);
      return;
    }

    default: {
      if (options.help) {
        Help.review(options);
        return;
      }

      if (options.watch) {
        try {
          await runElmReviewInWatchMode(options, errorHandler);
          return;
        } catch (error) {
          errorHandler(error);
        }
      }
    }
  }

  try {
    await runElmReview(options);
  } catch (error) {
    errorHandler(error);
  }
}

module.exports = main;

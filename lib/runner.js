#!/usr/bin/env node

/**
 * @import {ReviewApp, FileReceipt} from './types/app';
 * @import {AppHash} from './types/build';
 * @import {ApplicationElmJson, Dependencies, ElmFile, ElmJsonData, ExtraFileRequest, LinksToRuleDocs, NonElmFiles, Readme} from './types/content';
 * @import {FixMode} from './types/fix';
 * @import {Options} from './types/options';
 * @import {ReportedError} from './types/report';
 * @import {RunOptions} from'./types/runner';
 * @import {SuppressedErrorsFile} from './types/suppressed';
 */
const exit = require('../vendor/exit');
const AppWrapper = require('./app-wrapper');
const Autofix = require('./autofix');
const {getProjectFiles} = require('./elm-files');
const ErrorMessage = require('./error-message');
const ExtraFiles = require('./extra-files');
const Hash = require('./hash');
const ModuleCache = require('./module-cache');
const ProjectDependencies = require('./project-dependencies');
const Report = require('./report');
const ReviewDependencies = require('./review-dependencies');
const {runReview, startReview, requestReview} = require('./run-review');
const AppState = require('./state');
const SuppressedErrors = require('./suppressed-errors');

/**
 * Send collected information to the Elm review application.
 *
 * @param {Options} options
 * @param {ReviewApp} app
 * @param {ElmJsonData} elmJsonData
 * @param {Readme | null} readme
 * @param {ElmFile[]} elmFiles
 * @param {Dependencies} dependencies
 * @param {SuppressedErrorsFile[]} suppressedErrors
 * @param {LinksToRuleDocs} linksToRuleDocs
 * @param {NonElmFiles} extraFiles
 * @returns {Promise<void>}
 */
async function sendProjectContent(
  options,
  app,
  elmJsonData,
  readme,
  elmFiles,
  dependencies,
  suppressedErrors,
  linksToRuleDocs,
  extraFiles
) {
  const filesPendingReceiptAcknowledgement = new Set(
    elmFiles.map((file) => file.path)
  );

  app.ports.collectElmJson.send(elmJsonData);

  if (readme) {
    app.ports.collectReadme.send(readme);
  }

  if (dependencies.length > 0) {
    app.ports.collectDependencies.send(dependencies);
  }

  if (suppressedErrors.length > 0) {
    app.ports.collectSuppressedErrors.send(suppressedErrors);
  }

  app.ports.collectLinks.send(linksToRuleDocs);
  app.ports.collectExtraFiles.send(extraFiles);

  await new Promise((/** @type {(value?: never) => void} */ resolve) => {
    app.ports.acknowledgeFileReceipt.subscribe(acknowledgeFileReceipt);
    for (const file of elmFiles) {
      app.ports.collectFile.send(file);
    }

    /**
     *
     * @param {FileReceipt} file
     * @returns {Promise<void>}
     */
    async function acknowledgeFileReceipt(file) {
      filesPendingReceiptAcknowledgement.delete(file.path);

      if (file.cacheRequest) {
        await ModuleCache.cacheFile(
          options,
          Hash.hash(file.cacheRequest.source),
          file.cacheRequest.ast
        );
      }

      if (filesPendingReceiptAcknowledgement.size === 0) {
        app.ports.acknowledgeFileReceipt.unsubscribe(acknowledgeFileReceipt);
        resolve();
      }
    }
  });
}

/**
 * @param {Options} options
 * @param {string} elmModulePath
 * @param {ApplicationElmJson} reviewElmJson
 * @param {AppHash} appHash
 * @returns  {Promise<RunOptions>}
 */
async function initializeApp(options, elmModulePath, reviewElmJson, appHash) {
  const app = AppWrapper.init(options, elmModulePath, {
    debug: options.debug,
    enableExtract: options.enableExtract,
    resultCacheFolder: options.resultCachePath(appHash),
    fixMode: fixMode(options),
    fixLimit: options.fixLimit ?? null,
    fileRemovalFixesEnabled: options.fileRemovalFixesEnabled,
    explainFixFailure: options.explainFixFailure,
    unsuppress: options.unsuppress,
    showBenchmark: options.showBenchmark,
    detailsMode: options.detailsMode,
    report: options.report === 'json' ? 'json' : 'human',
    rulesFilter: options.rulesFilter,
    ignoreProblematicDependencies: options.ignoreProblematicDependencies,
    directoriesToAnalyze: options.directoriesToAnalyze,
    ignoredDirs: options.ignoredDirs(),
    ignoredFiles: options.ignoredFiles(),
    writeSuppressionFiles: options.directoriesToAnalyze.length === 0
  });

  AppState.initializedApp();
  AppState.subscribe(app.ports.abort, throwOnError);
  AppState.subscribe(app.ports.abortWithDetails, ({title, message}) => {
    throw new ErrorMessage.CustomError(title, message);
  });
  AppState.subscribe(
    app.ports.abortForConfigurationErrors,
    /**
     * @param {ReportedError[]} errors
     * @returns {never}
     */
    (errors) => {
      void Report.report(options, {errors});
      exit(1);
    }
  );
  /** @type {(value: ExtraFileRequest[]) => void} */
  let r;
  const requestedExtraFilesP = new Promise(
    (/** @type {(value: ExtraFileRequest[]) => void } */ resolve) => {
      r = resolve;
    }
  );
  const extraFilesP = requestedExtraFilesP.then(ExtraFiles.collect);
  AppState.subscribe(
    // @ts-expect-error(TS2345): Type 'string' is not assignable to type 'ExtraFileRequest'.
    app.ports.requestReadingFiles,
    // @ts-expect-error(TS2454): `r` isn't assigned yet. Seems legit.
    r
  );

  ModuleCache.subscribe(options, app);
  Autofix.subscribe(options, app, reviewElmJson['elm-version']);
  if (options.watch) {
    AppState.subscribe(app.ports.reviewReport, async (result) => {
      await Promise.all([
        Report.report(options, result),
        result.suppressedErrors &&
          SuppressedErrors.write(options, result.suppressedErrors)
      ]);

      const shouldReReview = AppState.reviewFinished();
      if (shouldReReview) {
        startReview(options, app);
      }
    });
  }

  const elmSyntaxVersion =
    reviewElmJson.dependencies.direct['stil4m/elm-syntax'] ??
    reviewElmJson.dependencies.indirect['stil4m/elm-syntax'];

  const elmVersion = reviewElmJson['elm-version'];

  const suppressedErrorsP = SuppressedErrors.read(options);

  const linksToRuleDocsP = ReviewDependencies.collectRuleLinks(
    reviewElmJson.dependencies.direct,
    elmVersion
  );

  const {elmJsonData, elmFiles, sourceDirectories, readme} =
    // @ts-expect-error(TS2345): Options is `Options`, not `ReviewOptions`.
    await getProjectFiles(options, elmSyntaxVersion);
  const projectDepsP = ProjectDependencies.collect(
    options,
    elmJsonData.project,
    elmVersion
  );

  const [
    projectDeps,
    suppressedErrors,
    linksToRuleDocs,
    requestedExtraFiles,
    extraFiles
  ] = await Promise.all([
    projectDepsP,
    suppressedErrorsP,
    linksToRuleDocsP,
    requestedExtraFilesP,
    extraFilesP
  ]);

  await sendProjectContent(
    options,
    app,
    elmJsonData,
    readme,
    elmFiles,
    projectDeps,
    suppressedErrors,
    linksToRuleDocs,
    extraFiles
  );

  return {
    app,
    elmVersion,
    elmJsonData,
    elmFiles,
    sourceDirectories,
    requestedExtraFiles
  };
}

/**
 * @param {Options} options
 * @returns {FixMode}
 */
function fixMode(options) {
  if (options.fix) {
    return 'fix';
  }

  if (options.fixAll) {
    return 'fixAll';
  }

  return 'dontfix';
}

/**
 * @param {string} message
 * @returns {void}
 */
function throwOnError(message) {
  throw new ErrorMessage.CustomError(
    'UNEXPECTED CRASH',
    // prettier-ignore
    `I encountered an unexpected crash with the following error message:

${message}`
  );
}

module.exports = {
  initializeApp,
  runReview,
  requestReview
};

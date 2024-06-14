#!/usr/bin/env node

const Hash = require('./hash');
const Report = require('./report');
const AppState = require('./state');
const Autofix = require('./autofix');
const AppWrapper = require('./app-wrapper');
const ExtraFiles = require('./extra-files');
const ModuleCache = require('./module-cache');
const ErrorMessage = require('./error-message');
const {getProjectFiles} = require('./elm-files');
const SuppressedErrors = require('./suppressed-errors');
const ReviewDependencies = require('./review-dependencies');
const ProjectDependencies = require('./project-dependencies');
const {runReview, startReview, requestReview} = require('./run-review');
const exit = require('../vendor/exit');

/**
 * @typedef { import("./types/options").Options } Options
 * @typedef { import("./types/app").App } App
 * @typedef { import("./types/app").FileReceipt } FileReceipt
 * @typedef { import("./types/content").ElmFile } ElmFile
 * @typedef { import("./types/content").Readme } Readme
 * @typedef { import("./types/content").ElmJsonData } ElmJsonData
 * @typedef { import("./types/content").Dependencies } Dependencies
 * @typedef { import("./types/content").LinksToRuleDocs } LinksToRuleDocs
 * @typedef { import("./types/content").NonElmFiles } NonElmFiles
 * @typedef { import("./types/suppressed").SuppressedErrorsFile } SuppressedErrorsFile
 */

/**
 * Send collected information to the Elm review application.
 * @param {Options} options
 * @param {App} app
 * @param {ElmJsonData} elmJsonData
 * @param {Readme | null} readme
 * @param {ElmFile[]} elmFiles
 * @param {Dependencies} dependencies
 * @param {SuppressedErrorsFile[]} suppressedErrors
 * @param {LinksToRuleDocs} linksToRuleDocs
 * @param {NonElmFiles} extraFiles
 * @returns {Promise<void>}
 */
function sendProjectContent(
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

  return new Promise((resolve) => {
    app.ports.acknowledgeFileReceipt.subscribe(acknowledgeFileReceipt);
    elmFiles.forEach((file) => {
      app.ports.collectFile.send(file);
    });

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

async function initializeApp(options, elmModulePath, reviewElmJson, appHash) {
  const app = AppWrapper.init(options, elmModulePath, {
    debug: options.debug,
    enableExtract: options.enableExtract,
    resultCacheFolder: options.resultCachePath(appHash),
    fixMode: fixMode(options),
    fixLimit: options.fixLimit || null,
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
  AppState.subscribe(app.ports.abortForConfigurationErrors, (errors) => {
    Report.report(options, {errors});
    exit(1);
  });
  let resolve = null;
  const requestedExtraFilesP = new Promise((r) => {
    resolve = r;
  });
  const extraFilesP = requestedExtraFilesP.then(ExtraFiles.collect);
  // eslint-disable-next-line @typescript-eslint/ban-ts-comment
  // @ts-ignore
  AppState.subscribe(app.ports.requestReadingFiles, resolve);

  ModuleCache.subscribe(options, app);
  Autofix.subscribe(options, app, reviewElmJson['elm-version']);
  if (options.watch) {
    AppState.subscribe(app.ports.reviewReport, (result) => {
      return Promise.all([
        Report.report(options, result),
        result.suppressedErrors &&
          SuppressedErrors.write(options, result.suppressedErrors)
      ]).then(() => {
        const shouldReReview = AppState.reviewFinished();
        if (shouldReReview) {
          return startReview(options, app);
        }
      });
    });
  }

  const elmSyntaxVersion =
    reviewElmJson.dependencies.direct['stil4m/elm-syntax'] ||
    reviewElmJson.dependencies.indirect['stil4m/elm-syntax'];

  const elmVersion = reviewElmJson['elm-version'];

  const suppressedErrorsP = SuppressedErrors.read(options);

  const linksToRuleDocsP = ReviewDependencies.collectRuleLinks(
    reviewElmJson.dependencies.direct,
    elmVersion
  );

  const {elmJsonData, elmFiles, sourceDirectories, readme} =
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
 * @returns {'fix'|'fixAll'|'dontfix'}
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

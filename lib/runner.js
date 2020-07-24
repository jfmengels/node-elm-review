#!/usr/bin/env node

const cache = require('./cache');
const report = require('./report');
const AppState = require('./state');
const autofix = require('./autofix');
const AppWrapper = require('./app-wrapper');
const ErrorMessage = require('./error-message');
const {getProjectFiles} = require('./elm-files');
const projectDependencies = require('./project-dependencies');
const {getElmBinary, getElmVersion} = require('./elm-binary');
const {runReview, startReview, requestReview} = require('./run-review');

function sendProjectContent(
  options,
  app,
  elmJsonData,
  readme,
  elmFiles,
  dependencies,
  linksToRuleDocs
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

  app.ports.collectLinks.send(linksToRuleDocs);

  return new Promise((resolve) => {
    app.ports.acknowledgeFileReceipt.subscribe(acknowledgeFileReceipt);
    elmFiles.forEach((file) => {
      app.ports.collectFile.send(file);
    });

    async function acknowledgeFileReceipt(file) {
      filesPendingReceiptAcknowledgement.delete(file.path);

      if (file.cacheRequest) {
        await cache.cacheFile(options, file.cacheRequest);
      }

      if (filesPendingReceiptAcknowledgement.size === 0) {
        app.ports.acknowledgeFileReceipt.unsubscribe(acknowledgeFileReceipt);
        resolve();
      }
    }
  });
}

async function initializeApp(options, elmModulePath, reviewElmJson) {
  const app = AppWrapper.init(options, elmModulePath, {
    fixMode: fixMode(options),
    detailsMode: options.detailsMode,
    report: options.report === 'json' ? 'json' : 'human',
    rulesFilter: options.rules,
    ignoreProblematicDependencies: options.ignoreProblematicDependencies
  });

  AppState.initializedApp();
  AppState.subscribe(app.ports.abort, throwOnError);
  AppState.subscribe(app.ports.abortWithDetails, ({title, message}) => {
    throw new ErrorMessage.CustomError(title, message);
  });

  cache.subscribe(options, app);
  autofix.subscribe(options, app);
  if (options.watch) {
    AppState.subscribe(app.ports.reviewReport, (result) => {
      report(options, result);
      const shouldReReview = AppState.reviewFinished();
      if (shouldReReview) {
        return startReview(options, app);
      }
    });
  }

  const [
    {elmJsonData, elmFiles, sourcesDirectories, readme},
    elmVersion
  ] = await Promise.all([
    getProjectFiles(options),
    getElmBinary(options).then(getElmVersion)
  ]);
  const {projectDeps, linksToRuleDocs} = await projectDependencies.collect(
    options,
    elmJsonData.project,
    reviewElmJson.dependencies.direct,
    elmVersion
  );
  await sendProjectContent(
    options,
    app,
    elmJsonData,
    readme,
    elmFiles,
    projectDeps,
    linksToRuleDocs
  );

  return {
    app,
    elmVersion,
    elmJsonData,
    elmFiles,
    sourcesDirectories
  };
}

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
    /* eslint-disable prettier/prettier */
'UNEXPECTED CRASH',
`I encountered an unexpected crash with the following error message:

${message}`
      /* eslint-enable prettier/prettier */
  );
}

module.exports = {
  initializeApp,
  runReview,
  requestReview
};

#!/usr/bin/env node

const cache = require('./cache');
const report = require('./report');
const appState = require('./state');
const autofix = require('./autofix');
const appWrapper = require('./app-wrapper');
const errorMessage = require('./error-message');
const {getProjectFiles} = require('./elm-files');
const promisifyPort = require('./promisify-port');
const projectDependencies = require('./project-dependencies');
const {getElmBinary, getElmVersion} = require('./elm-binary');

function sendProjectContent(
  options,
  app,
  elmJsonData,
  readme,
  elmFiles,
  dependencies
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

async function runReview(options, app) {
  if (options.watch) {
    app.ports.startReview.send(null);
    return undefined;
  }

  const result = await promisifyPort({
    subscribeTo: app.ports.reviewReport,
    sendThrough: app.ports.startReview,
    data: null
  });

  report(options, result);

  return result.success;
}

async function initializeApp(options, elmModulePath) {
  const app = appWrapper.init(options, elmModulePath, {
    fixMode: fixMode(options),
    report: options.report === 'json' ? 'json' : 'human'
  });

  appState.initializedApp();
  appState.subscribe(app.ports.abort, throwOnError);

  cache.subscribe(options, app);
  autofix.subscribe(options, app);
  if (options.watch) {
    appState.subscribe(app.ports.reviewReport, (result) =>
      report(options, result)
    );
  }

  const [
    {elmJsonData, elmFiles, sourcesDirectories, readme},
    elmVersion
  ] = await Promise.all([
    getProjectFiles(options),
    getElmBinary(options).then(getElmVersion)
  ]);
  const projectDeps = await projectDependencies.collect(
    options,
    elmJsonData.project,
    elmVersion
  );
  await sendProjectContent(
    options,
    app,
    elmJsonData,
    readme,
    elmFiles,
    projectDeps
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
  throw new errorMessage.CustomError(
    /* eslint-disable prettier/prettier */
'UNEXPECTED CRASH',
`I encountered an unexpected crash with the following error message:

${message}`
      /* eslint-enable prettier/prettier */
  );
}

module.exports = {
  initializeApp,
  runReview
};

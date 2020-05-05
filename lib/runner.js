#!/usr/bin/env node

const projectDependencies = require('./project-dependencies');
const cache = require('./cache');
const styledMessage = require('./styled-message');
const autofix = require('./autofix');
const appState = require('./state');
const {getProjectFiles} = require('./elm-files');
const promisifyPort = require('./promisify-port');
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
    elmFiles.map(file => file.path)
  );

  app.ports.collectElmJson.send(elmJsonData);

  if (readme) {
    app.ports.collectReadme.send(readme);
  }

  if (dependencies.length > 0) {
    app.ports.collectDependencies.send(dependencies);
  }

  return new Promise(resolve => {
    app.ports.acknowledgeFileReceipt.subscribe(acknowledgeFileReceipt);
    elmFiles.forEach(file => {
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
    app.ports.startReview.send(true);
    return undefined;
  }

  const result = await promisifyPort({
    subscribeTo: app.ports.reviewReport,
    sendThrough: app.ports.startReview,
    data: true
  });

  if (options.json) {
    result.json.forEach(error => console.log(JSON.stringify(error)));
  } else {
    styledMessage.log(options, result.report);
  }

  return result.success;
}

async function initializeApp(options, elmModule) {
  const app = elmModule.Elm.Elm.Review.Main.init({
    flags: {
      fixMode: fixMode(options)
    }
  });

  appState.initializedApp();
  appState.subscribe(app.ports.abort, throwOnError);

  cache.subscribe(options, app);
  autofix.subscribe(options, app);
  if (options.watch) {
    appState.subscribe(
      app.ports.reviewReport,
      printReviewReportWithOptions(options)
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
    readme,
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

function printReviewReportWithOptions(options) {
  return result => {
    if (options.json) {
      result.json.forEach(error => console.log(JSON.stringify(error)));
    } else {
      styledMessage.log(options, result.report);
    }
  };
}

function throwOnError(errorMessage) {
  throw new Error(errorMessage);
}

module.exports = {
  initializeApp,
  runReview
};

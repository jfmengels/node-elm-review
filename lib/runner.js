#!/usr/bin/env node

const spawn = require('cross-spawn');
const projectDependencies = require('./project-dependencies');
const cache = require('./cache');
const styledMessage = require('./styled-message');
const autofix = require('./autofix');
const {getProjectFiles} = require('./elm-files');
const {getElmBinary, getElmVersion} = require('./elm-binary');

function sendProjectContent(app, elmJsonData, elmFiles, dependencies) {
  const filesPendingReceiptAcknowledgement = new Set(
    elmFiles.map(file => file.path)
  );

  app.ports.collectElmJson.send(elmJsonData);
  if (dependencies.length > 0) {
    app.ports.collectDependencies.send(dependencies);
  }

  return new Promise(resolve => {
    app.ports.acknowledgeFileReceipt.subscribe(acknowledgeFileReceipt);
    elmFiles.forEach(file => {
      app.ports.collectFile.send(file);
    });

    function acknowledgeFileReceipt(fileName) {
      filesPendingReceiptAcknowledgement.delete(fileName);

      if (filesPendingReceiptAcknowledgement.size === 0) {
        app.ports.acknowledgeFileReceipt.unsubscribe(acknowledgeFileReceipt);
        resolve();
      }
    }
  });
}

// TODO Format file before saving it.
// eslint-disable-next-line no-unused-vars
function formatFileContent(file) {
  return new Promise((resolve, reject) => {
    const child = spawn(
      'npx',
      ['--no-install', 'elm-format', '--stdin', '--yes', '--elm-version=0.19'],
      {shell: true}
    );

    child.on('data', newSource =>
      resolve({
        file: file.path,
        source: newSource
      })
    );
    child.on('error', reject);
    child.stdin.write(file.source);
    child.stdin.end();
  });
}

function runReview(options, app) {
  if (options.watch) {
    app.ports.startReview.send(true);
    return Promise.resolve();
  }

  return new Promise(resolve => {
    app.ports.reviewReport.subscribe(printReviewReport);
    app.ports.startReview.send(true);

    function printReviewReport(result) {
      console.log(styledMessage(options, result.report));
      return resolve(result.success);
    }
  });
}

let currentApp = null;
let printReviewReportForWatch = null;

async function initializeApp(options, elmModule) {
  if (currentApp) {
    currentApp.ports.abort.unsubscribe(throwOnError);
    if (options.watch) {
      currentApp.ports.reviewReport.unsubscribe(printReviewReportForWatch);
    }
  }

  const app = elmModule.Elm.Elm.Review.Main.init({
    flags: {
      fixMode: options.fix ? 'fix' : 'dontfix'
    }
  });
  currentApp = app;

  app.ports.abort.subscribe(throwOnError);
  cache.subscribe(options, app);
  autofix.subscribe(options, app);
  if (options.watch) {
    printReviewReportForWatch =
      printReviewReportForWatch || printReviewReportWithOptions(options);
    app.ports.reviewReport.subscribe(printReviewReportForWatch);
  }

  const [
    {elmJsonData, elmFiles, sourcesDirectories},
    elmVersion
  ] = await Promise.all([
    getProjectFiles(options),
    getElmBinary(options).then(getElmVersion)
  ]);
  const projectDeps = await projectDependencies.collect(
    elmJsonData.project,
    elmVersion
  );
  await sendProjectContent(app, elmJsonData, elmFiles, projectDeps);

  return {
    app,
    elmVersion,
    elmJsonData,
    elmFiles,
    sourcesDirectories
  };
}

function printReviewReportWithOptions(options) {
  return result => {
    console.log(styledMessage(options, result.report));
  };
}

function throwOnError(errorMessage) {
  throw new Error(errorMessage);
}

module.exports = {
  initializeApp,
  runReview
};

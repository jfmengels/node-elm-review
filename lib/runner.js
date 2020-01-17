#!/usr/bin/env node

const spawn = require('cross-spawn');
const dependencies = require('./dependencies');
const cache = require('./cache');
const styledMessage = require('./styled-message');
const autofix = require('./autofix');
const {getProjectFiles} = require('./elm-files');
const {getElmBinary, getElmVersion} = require('./elm-binary');

function sendProjectContent(app, elmJson, elmFiles, dependencies) {
  const filesPendingReceiptAcknowledgement = new Set(
    elmFiles.map(file => file.path)
  );

  app.ports.collectElmJson.send(elmJson);
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
  return new Promise(resolve => {
    app.ports.reviewReport.subscribe(printReviewReport);
    app.ports.startReview.send(true);

    function printReviewReport(result) {
      console.log(styledMessage(options, result.report));
      app.ports.reviewReport.unsubscribe(printReviewReport);
      return resolve(result.success);
    }
  });
}

let previousApp = null;
async function initializeApp(options, elmModule) {
  if (previousApp) {
    app.ports.abort.unsubscribe(throwOnError);
  }

  const app = elmModule.Elm.Elm.Review.Main.init({
    flags: {
      fixMode: options.fix ? 'fix' : 'dontfix'
    }
  });
  previousApp = app;

  app.ports.abort.subscribe(throwOnError);
  cache.subscribe(options, app);
  autofix.subscribe(options, app);

  const [
    {elmJson, elmFiles, sourcesDirectories},
    elmVersion
  ] = await Promise.all([
    getProjectFiles(options),
    getElmBinary(options).then(getElmVersion)
  ]);
  const projectDependencies = await dependencies.collect(elmJson, elmVersion);
  await sendProjectContent(app, elmJson, elmFiles, projectDependencies);

  return {
    app,
    elmVersion,
    elmJson,
    elmFiles,
    sourcesDirectories,
    projectDependencies
  };
}

function throwOnError(errorMessage) {
  throw new Error(errorMessage);
}

module.exports = {
  initializeApp,
  runReview
};

const {parentPort, workerData} = require('worker_threads');
const ElmCommunication = require('./elm-communication');
const loadCompiledElmApp = require('./load-compiled-app');
const ResultCache = require('./result-cache');

/**
 * @typedef { import("worker_threads").MessagePort } MessagePort
 */

const elmModule = loadCompiledElmApp(workerData.elmModulePath);

const app = elmModule.Elm.Elm.Review.Main.init({
  flags: {
    ...workerData.flags,
    logger: ElmCommunication.create(workerData.flags)
  }
});

const loadCachePromise = ResultCache.load(
  workerData.flags,
  workerData.flags.ignoredDirs,
  workerData.flags.ignoredFiles,
  workerData.flags.resultCacheFolder
);

if (parentPort) {
  subscribe(parentPort);
}

/**
 * @param {MessagePort} parentPort
 * @returns {void}
 */
function subscribe(parentPort) {
  parentPort.on('message', ([port, data]) => {
    if (port === 'startReview' || port === 'startGeneratingSuppressions') {
      loadCachePromise.then(() => {
        app.ports[port].send(data);
      });
    } else {
      app.ports[port].send(data);
    }
  });

  app.ports.requestReadingFiles.subscribe((data) => {
    parentPort.postMessage(['requestReadingFiles', data]);
  });
  app.ports.cacheFile.subscribe((data) => {
    parentPort.postMessage(['cacheFile', data]);
  });
  app.ports.acknowledgeFileReceipt.subscribe((data) => {
    parentPort.postMessage(['acknowledgeFileReceipt', data]);
  });
  app.ports.reviewReport.subscribe((data) => {
    parentPort.postMessage(['reviewReport', data]);
  });
  app.ports.askConfirmationToFix.subscribe((data) => {
    parentPort.postMessage(['askConfirmationToFix', data]);
  });
  app.ports.fixConfirmationStatus.subscribe((data) => {
    parentPort.postMessage(['fixConfirmationStatus', data]);
  });
  app.ports.abort.subscribe((data) => {
    parentPort.postMessage(['abort', data]);
  });
  app.ports.abortWithDetails.subscribe((data) => {
    parentPort.postMessage(['abortWithDetails', data]);
  });
  app.ports.abortForConfigurationErrors.subscribe((data) => {
    parentPort.postMessage(['abortForConfigurationErrors', data]);
  });
}

// Code very much inspired by
// https://blog.logrocket.com/a-complete-guide-to-threads-in-node-js-4fa3898fe74f/

const os = require('os');
const path = require('path');

/**
 * @typedef { import("./types/parse-elm").ParseJob } ParseJob
 * @typedef { import("./types/parse-elm").callback } callback
 * @typedef { import("./types/path").Path } Path
 * @typedef { import("./types/content").Source } Source
 * @typedef { import("./types/content").ElmFile } ElmFile
 */

/** A worker and the information whether it is currently busy.
 *
 * @typedef {Object} CustomWorker
 * @property {Worker} worker
 * @property {boolean} busy
 */

// We want to have as many worker threads as CPUs on the user's machine.
// Since the main thread is already one, we spawn (numberOfCpus - 1) workers.
const numberOfThreads = Math.max(1, os.cpus().length - 1);

/** @type {Array<CustomWorker>} */
const workers = new Array(numberOfThreads);

/** @type {Array<ParseJob>} */
const queue = [];

try {
  // Conditional imports, because `worker_threads` is not supported by default
  // on Node v10

  const {Worker} = require('worker_threads');

  module.exports = {
    parse,
    prepareWorkers: prepareWorkers(Worker),
    terminateWorkers
  };
} catch {
  // On Node v10, disable parsing files here, and let the Elm application handle
  // it instead.
  module.exports = {
    parse: () => Promise.resolve(null),
    prepareWorkers: () => null,
    terminateWorkers: () => null
  };
}

/** Prepare the workers.
 *
 * @param {typeof Worker} Worker
 * @return {(function(): void)|*}
 */
function prepareWorkers(Worker) {
  return () => {
    const pathToWorker = path.resolve(__dirname, 'parse-elm-worker.js');
    for (let i = 0; i < numberOfThreads; i++) {
      workers[i] = {
        worker: new Worker(pathToWorker),
        busy: false
      };
    }
  };
}

function terminateWorkers() {
  workers.forEach(({worker}) => worker.terminate());
}

// MAIN THREAD

/**
 *
 * @param {Path} elmParserPath
 * @param {Source} source
 * @return {Promise<ElmFile>}
 */
function parse(elmParserPath, source) {
  return new Promise((resolve, reject) => {
    const availableWorker = findInactiveWorker();
    /** @type {ParseJob} */
    const queueItem = {
      source,
      elmParserPath,
      callback: (/** @type {Error} */ error, /** @type {ElmFile} */ result) => {
        if (error) {
          return reject(error);
        }

        return resolve(result);
      }
    };
    if (availableWorker === null) {
      queue.push(queueItem);
      return;
    }

    runWorker(availableWorker, queueItem);
  });
}

/** Finds a non-busy worker.
 *
 * @return {CustomWorker | null}
 */
function findInactiveWorker() {
  for (const element of workers) {
    if (!element.busy) {
      return element;
    }
  }

  return null;
}

/**
 *
 * @param {CustomWorker} availableWorker
 * @param {ParseJob} queueItem
 * @return {Promise<void>}
 */
async function runWorker(availableWorker, queueItem) {
  availableWorker.busy = true;

  /** @param {ElmFile} result */
  const messageCallback = (result) => {
    queueItem.callback(null, result);
    cleanUp();
  };

  /** @param {Error} error */
  function errorCallback(error) {
    queueItem.callback(error);
    cleanUp();
  }

  function cleanUp() {
    availableWorker.worker.removeAllListeners('message');
    availableWorker.worker.removeAllListeners('error');
    availableWorker.busy = false;
    const nextJob = queue.pop();
    if (nextJob === undefined) {
      return null;
    }

    runWorker(availableWorker, nextJob);
  }

  availableWorker.worker.once('message', messageCallback);
  availableWorker.worker.once('error', errorCallback);
  availableWorker.worker.postMessage({
    source: queueItem.source,
    elmParserPath: queueItem.elmParserPath
  });
}

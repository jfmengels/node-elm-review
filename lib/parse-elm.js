/**
 * @file Parse Elm files in parallel using worker threads.
 *
 * This code was very much inspired by
 * <https://blog.logrocket.com/complete-guide-threads-node-js/>.
 */

/**
 * @import {Ast, ElmFile, Source} from './types/content';
 * @import {CustomWorker, ParseJob} from './types/parse-elm';
 * @import {Path} from './types/path';
 */
const os = require('node:os');
const path = require('pathe');

// We want to have as many worker threads as CPUs on the user's machine.
// Since the main thread is already one, we spawn (numberOfCpus - 1) workers.
const numberOfThreads = Math.max(1, os.cpus().length - 1);

/** @type {CustomWorker[]} */
const workers = Array.from({length: numberOfThreads});

/** @type {ParseJob[]} */
const queue = [];

const {Worker} = require('node:worker_threads');

/**
 * Prepare the workers.
 *
 * @param {typeof Worker} Worker
 * @returns {() => void}
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

/**
 * @returns {void}
 */
function terminateWorkers() {
  for (const {worker} of workers) void worker.terminate();
}

// MAIN THREAD

/**
 * @param {Path} elmParserPath
 * @param {Source} source
 * @returns {Promise<Ast>}
 */
async function parse(elmParserPath, source) {
  return await new Promise((resolve, reject) => {
    const availableWorker = findInactiveWorker();

    /** @type {ParseJob} */
    const queueItem = {
      source,
      elmParserPath,

      callback: (/** @type {Error | undefined} */ error, result) => {
        if (error === undefined) {
          resolve(result);
        } else {
          reject(error);
        }
      }
    };
    if (availableWorker === null) {
      queue.push(queueItem);
      return;
    }

    runWorker(availableWorker, queueItem);
  });
}

/**
 * Finds a non-busy worker.
 *
 * @returns {CustomWorker | null}
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
 * @param {CustomWorker} availableWorker
 * @param {ParseJob} queueItem
 * @returns {void}
 */
function runWorker(availableWorker, queueItem) {
  availableWorker.busy = true;

  /**
   * @param {ElmFile} result
   * @returns {void}
   */
  const messageCallback = (result) => {
    queueItem.callback(undefined, result);
    cleanUp();
  };

  /**
   * @param {Error} error
   * @returns {void}
   */
  function errorCallback(error) {
    queueItem.callback(error);
    cleanUp();
  }

  /**
   * @returns {void}
   */
  function cleanUp() {
    availableWorker.worker.removeAllListeners('message');
    availableWorker.worker.removeAllListeners('error');
    availableWorker.busy = false;
    const nextJob = queue.pop();
    if (nextJob === undefined) {
      return;
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

module.exports = {
  parse,
  prepareWorkers: prepareWorkers(Worker),
  terminateWorkers
};

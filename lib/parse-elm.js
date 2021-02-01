// Code very much inspired by
// https://blog.logrocket.com/a-complete-guide-to-threads-in-node-js-4fa3898fe74f/

const os = require('os');
const path = require('path');

// We want to have as many worker threads as CPUs on the user's machine.
// Since the main thread is already one, we spawn (numberOfCpus - 1) workers.
const numberOfThreads = Math.max(1, os.cpus().length - 1);
const workers = new Array(numberOfThreads);
const queue = [];

try {
  // Conditional imports, because `worker_threads` is not supported by default
  // on Node v10
  // eslint-disable-next-line node/no-unsupported-features/node-builtins
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

function parse(elmParserPath, source) {
  return new Promise((resolve, reject) => {
    const availableWorker = findInactiveWorker();
    const queueItem = {
      source,
      elmParserPath,
      callback: (error, result) => {
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

function findInactiveWorker() {
  for (const element of workers) {
    if (!element.busy) {
      return element;
    }
  }

  return null;
}

async function runWorker(availableWorker, queueItem) {
  availableWorker.busy = true;
  const messageCallback = (result) => {
    queueItem.callback(null, result);
    cleanUp();
  };

  function errorCallback(error) {
    queueItem.callback(error);
    cleanUp();
  }

  function cleanUp() {
    availableWorker.worker.removeAllListeners('message');
    availableWorker.worker.removeAllListeners('error');
    availableWorker.busy = false;
    if (queue.length === 0) {
      return null;
    }

    runWorker(availableWorker, queue.pop());
  }

  availableWorker.worker.once('message', messageCallback);
  availableWorker.worker.once('error', errorCallback);
  availableWorker.worker.postMessage({
    source: queueItem.source,
    elmParserPath: queueItem.elmParserPath
  });
}

// Code very much inspired by
// https://blog.logrocket.com/a-complete-guide-to-threads-in-node-js-4fa3898fe74f/

const queue = [];
const workers = [];

try {
  // Conditional imports, because `worker_threads` is not supported by default
  // on Node v10
  // eslint-disable-next-line node/no-unsupported-features/node-builtins
  const {Worker, isMainThread, parentPort} = require('worker_threads');
  const os = require('os');
  const elmModule = require('../build/parseElm');

  if (isMainThread) {
    for (let i = 0; i < Math.max(1, os.cpus().length - 2); i++) {
      workers[i] = {
        worker: new Worker(__filename),
        busy: false
      };
    }
  } else {
    const app = elmModule.Elm.ParseMain.init();

    parentPort.on('message', data => {
      workerParseElm(app, data).then(result => {
        parentPort.postMessage(result);
      });
    });
  }

  module.exports = parseElm;
} catch {
  module.exports = () => Promise.resolve(null);
}

// MAIN THREAD

function parseElm(file) {
  return new Promise((resolve, reject) => {
    const availableWorker = findInactiveWorker();
    const queueItem = {
      file,
      callback: (error, result) => {
        if (error) {
          return reject(error);
        }

        return resolve(result);
      }
    };
    if (availableWorker === null) {
      queue.push(queueItem);
      return null;
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
  const messageCallback = result => {
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

    runWorker(availableWorker, queue.shift());
  }

  availableWorker.worker.once('message', messageCallback);
  availableWorker.worker.once('error', errorCallback);
  availableWorker.worker.postMessage(queueItem.file);
}

// WORKER THREADS

function workerParseElm(app, file) {
  return new Promise(resolve => {
    app.ports.parseResult.subscribe(handleResult);
    function handleResult(result) {
      if (result.path === file.path) {
        app.ports.parseResult.unsubscribe(handleResult);
        resolve(result.ast);
      }
    }

    app.ports.requestParsing.send(file);
  });
}

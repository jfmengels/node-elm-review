const path = require('path');
const ElmCommunication = require('./elm-communication');
const loadCompiledElmApp = require('./load-compiled-app');

const {Worker} = require('worker_threads');

module.exports = {
  init: (options, elmModulePath, flags) => init(options, elmModulePath, flags),
  stop: () => {
    if (worker) {
      worker.terminate();
      worker = null;
      listeners = initializeListeners();
    }
  }
};

function init(options, elmModulePath, flags) {
  if (options.watch) {
    return initWithWorker(elmModulePath, flags);
  }

  return initWithoutWorker(elmModulePath, flags);
}

// WITH WORKER

const pathToWorker = path.resolve(__dirname, 'elm-app-worker.js');
let worker = null;
let listeners = initializeListeners();

const elmPortsInterfaceProxy = {
  get(_, port) {
    return {
      send: send(port),
      subscribe: subscribe(port),
      unsubscribe: unsubscribe(port)
    };
  }
};

function initWithWorker(elmModulePath, flags) {
  worker = new Worker(pathToWorker, {
    workerData: {
      elmModulePath,
      flags
    }
  });

  worker.on('message', ([port, data]) => {
    if (listeners[port]) {
      listeners[port].forEach((fn) => fn(data));
    }
  });

  return {
    ports: new Proxy(worker, elmPortsInterfaceProxy)
  };
}

function send(port) {
  return (data) => {
    if (worker) {
      worker.postMessage([port, data]);
    }
  };
}

function subscribe(port) {
  return (callback) => {
    listeners[port].push(callback);
  };
}

function unsubscribe(port) {
  return (callback) => {
    listeners[port] = listeners[port].filter((fn) => fn === callback);
  };
}

function initializeListeners() {
  return {
    requestReadingFiles: [],
    cacheFile: [],
    acknowledgeFileReceipt: [],
    reviewReport: [],
    askConfirmationToFix: [],
    fixConfirmationStatus: [],
    abort: [],
    abortWithDetails: [],
    abortForConfigurationErrors: []
  };
}

// WITHOUT WORKER

function initWithoutWorker(elmModulePath, flags) {
  const elmModule = loadCompiledElmApp(elmModulePath);
  const app = elmModule.Elm.Elm.Review.Main.init({
    flags: {...flags, logger: ElmCommunication.create(flags)}
  });
  return app;
}

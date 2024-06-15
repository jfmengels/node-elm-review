const path = require('path');
const ElmCommunication = require('./elm-communication');
const loadCompiledElmApp = require('./load-compiled-app');

/**
 * @typedef { import('./types/options').Options } Options
 * @typedef { import('./types/options').ReviewOptions } ReviewOptions
 * @typedef { import('./types/app').App } App
 * @typedef { import('./types/app-wrapper').Exports } Exports
 */

/**
 * // `@template` should be @typeParam, but TS is acting up.
 *
 * @template T
 * @typedef { import('./types/promisify-port').CallbackFn<T> } CallbackFn
 */

/**
 * // `@template` should be @typeParam, but TS is acting up.
 *
 * @template T
 * @typedef { import('./types/promisify-port').Listened<T> } Listened
 */

/**
 * @template T
 * @template U
 * @typedef { import('./types/app-wrapper').Ports<T, U> } Ports
 */

try {
  // Conditional imports, because `worker_threads` is not supported by default
  // on Node v10

  const {Worker} = require('worker_threads');

  /** @type {Exports} */
  module.exports = {
    init: (options, elmModulePath, flags) =>
      init(Worker, options, elmModulePath, flags),
    stop: () => {
      if (worker) {
        worker.terminate();
        worker = null;
        listeners = initializeListeners();
      }
    }
  };
} catch {
  /** @type {Exports} */
  module.exports = {
    init: (_options, elmModulePath, flags) =>
      initWithoutWorker(elmModulePath, flags),
    stop: () => {}
  };
}

/**
 * @param {typeof import('worker_threads').Worker} Worker
 * @param {Options} options
 * @param {string} elmModulePath
 * @param {Options} flags
 */
function init(Worker, options, elmModulePath, flags) {
  if (options.watch) {
    return initWithWorker(Worker, elmModulePath, flags);
  }

  return initWithoutWorker(elmModulePath, flags);
}

// WITH WORKER

const pathToWorker = path.resolve(__dirname, 'elm-app-worker.js');
/** @type {Worker | null} */
let worker = null;
let listeners = initializeListeners();

/** @type {ProxyHandler<Worker>} */
const elmPortsInterfaceProxy = {
  /**
   * @template T
   * @template U
   * @param {unknown} _
   * @param {string | symbol} port
   * @returns {Ports<T, U>}
   */
  get(_, port) {
    return {
      send: send(port),
      subscribe: subscribe(port),
      unsubscribe: unsubscribe(port)
    };
  }
};

/**
 * @param {typeof import('worker_threads').Worker} Worker
 * @param {string} elmModulePath
 * @param {Options} flags
 */
function initWithWorker(Worker, elmModulePath, flags) {
  worker = new Worker(pathToWorker, {
    workerData: {
      elmModulePath,
      flags
    }
  });

  worker.on(
    'message',
    (/** @type {[string | symbol, unknown]} */ [port, data]) => {
      if (/** @type Listened<unknown>[] */ listeners[port]) {
        /** @type Listened<unknown>[] */ (listeners[port]).forEach((fn) =>
          fn(data)
        );
      }
    }
  );

  return {
    ports: new Proxy(worker, elmPortsInterfaceProxy)
  };
}

/**
 * @param {string | symbol} port
 */
function send(port) {
  return (/** @type {unknown} */ data) => {
    if (worker) {
      worker.postMessage([port, data]);
    }
  };
}

/**
 * @template T
 * @param {string | symbol} port
 * @returns {CallbackFn<T>}
 */
function subscribe(port) {
  return (callback) => {
    // @ts-expect-error - TS dislikes casting `T` to `unknown` for some reason.
    listeners[port].push(callback);
  };
}

/**
 * @template T
 * @param {string | symbol} port
 * @returns {CallbackFn<T>}
 */
function unsubscribe(port) {
  return (callback) => {
    listeners[port] = listeners[port].filter(
      (/** @type {Listened<unknown>} */ fn) => fn === callback
    );
  };
}

/**
 * @returns { Record<string | symbol, Listened<unknown>[] >}
 */
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

/**
 * @param {string} elmModulePath
 * @param {Options} flags
 */
function initWithoutWorker(elmModulePath, flags) {
  const elmModule = loadCompiledElmApp(elmModulePath);
  const app = elmModule.Elm.Elm.Review.Main.init({
    flags: {...flags, logger: ElmCommunication.create(flags)}
  });
  return app;
}

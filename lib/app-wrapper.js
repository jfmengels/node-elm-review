/**
 * @import {ReviewApp} from './types/app'
 * @import {WorkerData} from './types/elm-app-wrapper';
 * @import {Flags} from './types/flags'
 * @import {Options} from './types/options'
 * @import {Path} from './types/path'
 * @import {CallbackFn, Listened, Port} from './types/promisify-port'
 */
const path = require('pathe');
const {Worker} = require('node:worker_threads');
const ElmCommunication = require('./elm-communication');
const loadCompiledElmApp = require('./load-compiled-app');

/**
 * @param {Options} options
 * @param {string} elmModulePath
 * @param {Flags} flags
 * @returns {ReviewApp}
 */
function init(options, elmModulePath, flags) {
  if (options.watch) {
    return initWithWorker(elmModulePath, flags);
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
  // `@template` should be @typeParam, but TS is acting up.
  /**
   * @template T
   * @template U
   * @param {Worker} _
   * @param {string | symbol} port
   * @returns {Port<T, U>}
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
 * @param {Path} elmModulePath
 * @param {Flags} flags
 * @returns {ReviewApp}
 */
function initWithWorker(elmModulePath, flags) {
  worker = new Worker(pathToWorker, {
    workerData: /** @satisfies {WorkerData} */ ({
      elmModulePath,
      flags
    })
  });

  worker.on(
    'message',
    (/** @type {[string | symbol, unknown]} */ [port, data]) => {
      if (listeners[port]) {
        for (const fn of listeners[port]) fn(data);
      }
    }
  );

  return {
    // @ts-expect-error(TS2740): This is a `Worker`, which doesn't conform to the `App` interface.
    ports: new Proxy(worker, elmPortsInterfaceProxy)
  };
}

/**
 * @param {string | symbol} port
 * @returns {Listened<unknown>}
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
  // eslint-disable-next-line promise/prefer-await-to-callbacks -- Callbacks are still needed here.
  return (callback) => {
    // @ts-expect-error(TS2345): TS dislikes casting `T` to `unknown` for some reason.
    listeners[port].push(callback);
  };
}

/**
 * @template T
 * @param {string | symbol} port
 * @returns {CallbackFn<T>}
 */
function unsubscribe(port) {
  // eslint-disable-next-line promise/prefer-await-to-callbacks -- Callbacks are still needed here.
  return (callback) => {
    listeners[port] = listeners[port].filter((fn) => fn === callback);
  };
}

/**
 * @returns {Record<string | symbol, Listened<unknown>[]>}
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
 * @param {Flags} flags
 * @returns {ReviewApp}
 */
function initWithoutWorker(elmModulePath, flags) {
  const elmModule = loadCompiledElmApp(elmModulePath);
  const app = elmModule.Elm.Elm.Review.Main.init({
    flags: {...flags, logger: ElmCommunication.create(flags)}
  });
  return app;
}

/**
 * @returns {void}
 */
function stop() {
  if (worker) {
    void worker.terminate();
    worker = null;
    listeners = initializeListeners();
  }
}

module.exports = {
  init,
  stop
};

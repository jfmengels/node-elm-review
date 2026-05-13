/**
 * @import {MessagePort} from 'node:worker_threads';
 * @import {Ports} from './types/app';
 * @import {WorkerData} from './types/elm-app-wrapper';
 * @import {SendPort} from './types/promisify-port';
 * @import {WorkerThreads} from './types/worker';
 */

const workerThreads = require("node:worker_threads");
const ElmCommunication = require("./elm-communication");
const loadCompiledElmApp = require("./load-compiled-app");
const ResultCache = require("./result-cache");

const [elmModulePath, ...args] = process.argv.slice(2);
console.log(elmModulePath, args);

/**
 * @type {WorkerThreads<WorkerData>}
 */
const {parentPort, workerData} = workerThreads;

const elmModule = loadCompiledElmApp(elmModulePath);

const app = elmModule.Elm.Elm.Review.NodeMain.init({
  flags: {
    args,
    env: process.env,
    logger: undefined
  }
});

const loadCachePromise = Promise.resolve();
  /*ResultCache.load(
  workerData.flags,
  workerData.flags.ignoredDirs,
  workerData.flags.ignoredFiles,
  workerData.flags.resultCacheFolder
);*/

if (parentPort) {
  subscribe(parentPort);
}

/**
 * @param {MessagePort} parentPort
 * @returns {void}
 */
function subscribe(parentPort) {
  parentPort.on(
    "message",

    async (/** @type {[keyof Ports, unknown]}  */ [port, data]) => {
      if (port === "startReview" || port === "startGeneratingSuppressions") {
        await loadCachePromise;
      }

      /** @type {SendPort<unknown>} */ (app.ports[port]).send(data);
    }
  );
}

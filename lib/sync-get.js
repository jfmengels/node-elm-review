const path = require('path');
const {
  Worker,
  MessageChannel,
  receiveMessageOnPort
} = require('worker_threads');

module.exports = {
  startWorker
};

/** Start a worker thread and return a `syncGetWorker`
 * capable of making sync requests until shut down.
 *
 * @return {{get: (url : string) => string, shutDown: () => void}}
 */
function startWorker() {
  const {port1: localPort, port2: workerPort} = new MessageChannel();
  const sharedLock = new SharedArrayBuffer(4);
  const sharedLockArray = new Int32Array(sharedLock);
  const workerPath = path.resolve(__dirname, 'sync-get-worker.js');
  const worker = new Worker(workerPath, {
    workerData: {sharedLock, requestPort: workerPort},
    transferList: [workerPort]
  });

  /**
   * @param {string} url
   * @return {string}
   */
  function get(url) {
    worker.postMessage(url);
    Atomics.wait(sharedLockArray, 0, 0); // Blocks until notified at index 0.
    const response = receiveMessageOnPort(localPort);
    if (!response || !response.message) {
      return '';
    }

    if (response.message.error) {
      throw response.message.error;
    } else {
      return response.message;
    }
  }

  /** Shut down the worker thread.
   *
   * @returns {void}
   */
  function shutDown() {
    localPort.close();
    worker.terminate();
  }

  return {get, shutDown};
}

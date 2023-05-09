/**
 * Allows to treat a pair of ports as one promise.
 * It sends a message into `sendTrough` and resolves the promise with the first "response" data on `subscribeTo`.
 * @template DataIn,DataOut
 * @param {import("./types/promisify-port").PortsToPromise<DataIn, DataOut>} obj
 * @returns {PromiseLike<DataOut>}
 */
function promisifyPort({subscribeTo, sendThrough, data}) {
  return new Promise((resolve) => {
    /**
     * @param {DataOut} result
     * @returns void
     */
    const handler = (result) => {
      subscribeTo.unsubscribe(handler);
      resolve(result);
    };

    subscribeTo.subscribe(handler);
    sendThrough.send(data);
  });
}

module.exports = promisifyPort;

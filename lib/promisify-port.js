/**
 * @import {PortsToPromise} from './types/promisify-port';
 */

module.exports = promisifyPort;

/**
 * Allows to treat a pair of ports as one promise.
 * It sends a message into `sendTrough` and resolves the promise with the first "response" data on `subscribeTo`.
 *
 * @template DataIn,DataOut
 * @param {PortsToPromise<DataIn, DataOut>} obj
 * @returns {PromiseLike<DataOut>}
 */
function promisifyPort({subscribeTo, sendThrough, data}) {
  return new Promise((resolve) => {
    /**
     * @param {DataOut} result
     * @returns {void}
     */
    const handler = (result) => {
      subscribeTo.unsubscribe(handler);
      resolve(result);
    };

    subscribeTo.subscribe(handler);
    sendThrough.send(data);
  });
}

/**
 * @callback HandlerFn
 * @param {function} handler
 * @return {void}
 */

/**
 * Allows to treat a pair of ports as one promise.
 * It sends a message into `sendTrough` and resolves the promise with the first "response" data on `subscribeTo`.
 *
 * @template DataIn,DataOut
 * @param {object} obj
 * @param {{ subscribe: HandlerFn, unsubscribe: HandlerFn}} obj.subscribeTo - port to receive the action result
 * @param {{send: (data: DataIn) => void }} obj.sendThrough - port to trigger an action
 * @param {DataIn} obj.data - to trigger an action
 * @returns {PromiseLike<DataOut>}
 */
function promisifyPort({subscribeTo, sendThrough, data}) {
  return new Promise((resolve) => {
    /**
     * @param {DataOut} result
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

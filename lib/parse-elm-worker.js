// Code very much inspired by
// https://blog.logrocket.com/a-complete-guide-to-threads-in-node-js-4fa3898fe74f/

// eslint-disable-next-line node/no-unsupported-features/node-builtins
const {parentPort} = require('worker_threads');
const elmModule = require('../build/parseElm');
const promisifyPort = require('./promisify-port');

const app = elmModule.Elm.ParseMain.init();

parentPort.on('message', source => {
  workerParseElm(app, source).then(result => {
    parentPort.postMessage(result);
  });
});

function workerParseElm(app, source) {
  return promisifyPort({
    subscribeTo: app.ports.parseResult,
    sendThrough: app.ports.requestParsing,
    data: source
  });
}

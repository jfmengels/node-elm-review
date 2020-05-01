// Code very much inspired by
// https://blog.logrocket.com/a-complete-guide-to-threads-in-node-js-4fa3898fe74f/

// eslint-disable-next-line node/no-unsupported-features/node-builtins
const {parentPort} = require('worker_threads');
const elmModule = require('../build/parseElm');

const app = elmModule.Elm.ParseMain.init();

parentPort.on('message', data => {
  workerParseElm(app, data).then(result => {
    parentPort.postMessage(result);
  });
});

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

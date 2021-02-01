// Code very much inspired by
// https://blog.logrocket.com/a-complete-guide-to-threads-in-node-js-4fa3898fe74f/

// eslint-disable-next-line node/no-unsupported-features/node-builtins
const {parentPort} = require('worker_threads');
const promisifyPort = require('./promisify-port');

const appForElmModule = Object.create(null);

parentPort.on('message', (queueItem) => {
  workerParseElm(queueItem).then((result) => {
    parentPort.postMessage(result);
  });
});

function workerParseElm({source, elmParserPath}) {
  if (!appForElmModule[elmParserPath]) {
    const elmParser = require(elmParserPath);
    const app = elmParser.Elm.ParseMain.init();
    appForElmModule[elmParserPath] = app;
  }

  const app = appForElmModule[elmParserPath];
  return promisifyPort({
    subscribeTo: app.ports.parseResult,
    sendThrough: app.ports.requestParsing,
    data: source
  });
}

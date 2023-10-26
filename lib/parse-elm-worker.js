// Code very much inspired by
// https://blog.logrocket.com/a-complete-guide-to-threads-in-node-js-4fa3898fe74f/

const {parentPort} = require('worker_threads');
const promisifyPort = require('./promisify-port');

/**
 * @typedef { import("worker_threads").MessagePort } MessagePort
 * @typedef { import("./types/path").Path } Path
 * @typedef { import("./types/content").ElmFile } ElmFile
 * @typedef { import("./types/parse-elm").ParserApp } ParserApp
 * @typedef { import("./types/parse-elm").ParseJob } ParseJob
 */

const appForElmModule = Object.create(null);

if (parentPort) {
  subscribe(parentPort);
}

/**
 * @param {MessagePort} parentPort
 * @returns {void}
 */
function subscribe(parentPort) {
  parentPort.on('message', (queueItem) => {
    workerParseElm(queueItem).then((result) => {
      parentPort.postMessage(result);
    });
  });
}

/**
 *
 * @param {ParseJob} queueItem
 * @return {PromiseLike<ElmFile>}
 */
function workerParseElm({source, elmParserPath}) {
  /** @type {ParserApp} */
  let app = appForElmModule[elmParserPath];
  if (!app) {
    const elmParser = require(elmParserPath);
    app = elmParser.Elm.ParseMain.init();
    appForElmModule[elmParserPath] = app;
  }

  return promisifyPort({
    subscribeTo: app.ports.parseResult,
    sendThrough: app.ports.requestParsing,
    data: source
  });
}

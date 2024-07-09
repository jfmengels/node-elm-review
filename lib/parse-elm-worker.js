// Code very much inspired by
// https://blog.logrocket.com/a-complete-guide-to-threads-in-node-js-4fa3898fe74f/

const {parentPort} = require('node:worker_threads');
const promisifyPort = require('./promisify-port');

/**
 * @import {MessagePort} from "worker_threads"
 * @import {ElmFile} from "./types/content"
 * @import {ParserApp} from "./types/parse-elm"
 * @import {ParseJob} from "./types/parse-elm"
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
 * @param {ParseJob} queueItem
 * @returns {PromiseLike<ElmFile>}
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
    // @ts-expect-error(TS2322): TS wants an `ElmJson`, but we're giving a string.
    data: source
  });
}

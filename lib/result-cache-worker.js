/**
 * @import {MessagePort} from 'node:worker_threads';
 */
const path = require('pathe');
const {parentPort} = require('node:worker_threads');
const fs = require('graceful-fs');
const ResultCacheJson = require('./result-cache-json');

if (parentPort) {
  subscribe(parentPort);
}

/**
 * @param {MessagePort} parentPort
 * @returns {void}
 */
function subscribe(parentPort) {
  parentPort.on('message', ({filePath, cacheEntry, cacheKey}) => {
    try {
      fs.mkdirSync(path.dirname(filePath), {recursive: true});
    } catch {}

    fs.writeFile(
      filePath,
      JSON.stringify(cacheEntry, ResultCacheJson.replacer, 0),
      'utf8',
      () => {
        parentPort?.postMessage(cacheKey);
      }
    );
  });
}

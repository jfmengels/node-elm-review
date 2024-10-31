const path = require('node:path');
const {parentPort} = require('node:worker_threads');
const fs = require('graceful-fs');
const ResultCacheJson = require('./result-cache-json');

if (parentPort) {
  subscribe(parentPort);
}

function subscribe(parentPort) {
  parentPort.on('message', ({filePath, cacheEntry, cacheKey}) => {
    try {
      fs.mkdirSync(path.dirname(filePath), {recursive: true});
    } catch {}

    return fs.writeFile(
      filePath,
      JSON.stringify(cacheEntry, ResultCacheJson.replacer, 0),
      'utf8',
      () => parentPort?.postMessage(cacheKey)
    );
  });
}

const fs = require('fs');
// eslint-disable-next-line node/no-unsupported-features/node-builtins
const {parentPort} = require('worker_threads');
const path = require('path');
const ResultCacheJson = require('./result-cache-json');

parentPort.on('message', async ({filePath, cacheEntry, cacheKey}) => {
  await fs.mkdir(path.dirname(filePath), {recursive: true}, () => {});
  return fs.writeFile(
    filePath,
    JSON.stringify(cacheEntry, ResultCacheJson.replacer, 0),
    'utf8',
    () => parentPort.postMessage(cacheKey)
  );
});

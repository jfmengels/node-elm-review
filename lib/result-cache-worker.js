// eslint-disable-next-line node/no-unsupported-features/node-builtins
const {parentPort} = require('worker_threads');
const path = require('path');
const fs = require('fs-extra');

parentPort.on('message', async ({filePath, cacheEntry, cacheKey}) => {
  await fs.mkdirp(path.dirname(filePath)).catch(() => {});
  return fs.writeJson(filePath, cacheEntry, {spaces: 0}, () =>
    parentPort.postMessage(cacheKey)
  );
});

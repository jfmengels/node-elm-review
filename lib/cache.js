const path = require('path');
const util = require('util');
const fs = require('fs-extra');
const AppState = require('./state');

const fsEnsureDir = util.promisify(fs.ensureDir);
const fsReadJson = util.promisify(fs.readJson);
const fsWriteJson = util.promisify(fs.writeJson);

async function getOrCompute(folder, key, fn) {
  const filepath = path.join(folder, `${key}.json`);

  const cachedResult = await fsReadJson(filepath).catch(() => null);
  if (cachedResult) {
    return cachedResult;
  }

  const result = await fn();

  fsEnsureDir(folder).then(() =>
    fsWriteJson(filepath, result)
  );

  return result;
}

module.exports = {
  getOrCompute
};

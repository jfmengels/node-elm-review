const path = require('path');
const util = require('util');
const fs = require('fs-extra');
const FS = require('./fs-wrapper');
const AppState = require('./state');

const fsEnsureDir = util.promisify(fs.ensureDir);
const fsWriteJson = util.promisify(fs.writeJson);

async function getOrCompute(folder, key, fn) {
  const filepath = path.join(folder, `${key}.json`);

  const cachedResult = await FS.readJsonFile(filepath).catch(() => null);
  if (cachedResult) {
    return cachedResult;
  }

  const result = await fn();
  if (result !== null) {
    cacheJsonFile(filepath, result);
  }

  return result;
}

/**
 * Set of folders that we already ensured exist.
 * @type {Set<string>}
 */
const ensuredFolders = new Set();

/**
 * Cache a file on the filesystem.
 * @param {string} filepath - Path to the file ending in ".json"
 * @param {Object} content
 * @returns {Promise<void>}
 */
async function cacheJsonFile(filepath, content) {
  const folder = path.dirname(filepath);
  if (!ensuredFolders.has(folder)) {
    await fsEnsureDir(folder);
    ensuredFolders.add(folder);
  }

  AppState.writingToFileSystemCacheStarted(filepath);
  return fsWriteJson(filepath, content).finally(() =>
    AppState.writingToFileSystemCacheFinished(filepath)
  );
}

module.exports = {
  cacheJsonFile,
  getOrCompute
};

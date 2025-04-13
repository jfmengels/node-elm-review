/**
 * @import {Path} from './types/path';
 */
const path = require('node:path');
const FS = require('./fs-wrapper');
const AppState = require('./state');

/**
 * @template T
 * @param {Path} folder
 * @param {string} key
 * @param {() => Promise<T | null>} fn
 * @returns {Promise<T | null>}
 */
async function getOrCompute(folder, key, fn) {
  const filepath = path.join(folder, `${key}.json`);

  const cachedResult = await FS.readJsonFile(filepath).catch(() => null);
  if (cachedResult) {
    return /** @type {T} */ (cachedResult);
  }

  const result = await fn();
  if (result !== null) {
    void cacheJsonFile(filepath, result);
  }

  return result;
}

/**
 * Set of folders that we already ensured exist.
 *
 * @type {Set<string>}
 */
const ensuredFolders = new Set();

/**
 * Cache a file on the filesystem.
 *
 * @param {string} filepath - Path to the file ending in ".json"
 * @param {unknown} content
 * @returns {Promise<void>}
 */
async function cacheJsonFile(filepath, content) {
  const folder = path.dirname(filepath);
  if (!ensuredFolders.has(folder)) {
    await FS.mkdirp(folder);
    ensuredFolders.add(folder);
  }

  AppState.writingToFileSystemCacheStarted(filepath);
  await FS.writeJson(filepath, content, 0).finally(() =>
    AppState.writingToFileSystemCacheFinished(filepath)
  );
}

module.exports = {
  cacheJsonFile,
  getOrCompute
};

const path = require('path');
const util = require('util');
const crypto = require('crypto');
const fs = require('fs-extra');
const appState = require('./state');

const fsEnsureDir = util.promisify(fs.ensureDir);
const fsReadJson = util.promisify(fs.readJson);
const fsWriteJson = util.promisify(fs.writeJson);

function subscribe(options, app) {
  appState.subscribe(app.ports.cacheFile, (entry) => cacheFile(options, entry));
}

let hasAlreadyEnsuredDir = false;

async function cacheFile(options, {source, ast}) {
  const fileCachePath = options.fileCachePath();
  if (!hasAlreadyEnsuredDir) {
    await fsEnsureDir(fileCachePath);
    hasAlreadyEnsuredDir = true;
  }

  const sourceHash = hash(source);
  appState.writingToFileSystemCacheStarted(sourceHash);
  return fsWriteJson(
    path.join(fileCachePath, `${sourceHash}.json`),
    ast
  ).finally(() => appState.writingToFileSystemCacheFinished(sourceHash));
}

function readAstFromFSCache(options, source) {
  return fsReadJson(
    path.join(options.fileCachePath(), `${hash(source)}.json`)
  ).catch(() => null);
}

function hash(content) {
  return crypto.createHash('md5').update(content).digest('hex');
}

module.exports = {
  subscribe,
  cacheFile,
  readAstFromFSCache
};

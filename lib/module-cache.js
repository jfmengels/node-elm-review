const path = require('path');
const util = require('util');
const fs = require('fs-extra');
const AppState = require('./state');
const Hash = require('./hash');

const fsEnsureDir = util.promisify(fs.ensureDir);
const fsReadJson = util.promisify(fs.readJson);
const fsWriteJson = util.promisify(fs.writeJson);

function subscribe(options, app) {
  AppState.subscribe(app.ports.cacheFile, ({source, ast}) =>
    // TODO Do this in a thread
    cacheFile(options, Hash.hash(source), ast)
  );
}

let hasAlreadyEnsuredDir = false;

async function cacheFile(options, fileHash, ast) {
  const fileCachePath = options.fileCachePath();
  if (!hasAlreadyEnsuredDir) {
    await fsEnsureDir(fileCachePath);
    hasAlreadyEnsuredDir = true;
  }

  AppState.writingToFileSystemCacheStarted(fileHash);
  return fsWriteJson(
    path.join(fileCachePath, `${fileHash}.json`),
    ast
  ).finally(() => AppState.writingToFileSystemCacheFinished(fileHash));
}

function readAstFromFSCache(options, fileHash) {
  return fsReadJson(
    path.join(options.fileCachePath(), `${fileHash}.json`)
  ).catch(() => null);
}

module.exports = {
  subscribe,
  cacheFile,
  readAstFromFSCache
};

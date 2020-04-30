const path = require('path');
const util = require('util');
const crypto = require('crypto');
const fs = require('fs-extra');

const fsEnsureDir = util.promisify(fs.ensureDir);
const fsReadJson = util.promisify(fs.readJson);
const fsWriteJson = util.promisify(fs.writeJson);

let currentApp = null;
let cacheFileFunction = null;
const filesBeingCached = new Set();
let exitRequest = {requested: false};

const elmFilesCacheForWatch = [];

let hasEnsuredDir = false;

function subscribe(options, app) {
  cacheFileFunction = entry => cacheFile(options, entry);
  if (currentApp) {
    currentApp.ports.cacheFile.unsubscribe(cacheFileFunction);
  }

  currentApp = app;
  app.ports.cacheFile.subscribe(cacheFileFunction);
}

async function cacheFile(options, {source, ast}) {
  const fileCachePath = options.fileCachePath();
  if (!hasEnsuredDir) {
    await fsEnsureDir(fileCachePath);
    hasEnsuredDir = true;
  }

  const sourceHash = hash(source);
  filesBeingCached.add(sourceHash);
  return fsWriteJson(
    path.join(fileCachePath, `${sourceHash}.json`),
    ast
  ).finally(removeFileBeingCached(sourceHash));
}

function removeFileBeingCached(sourceHash) {
  return () => {
    filesBeingCached.delete(sourceHash);
    if (filesBeingCached.size === 0 && exitRequest.requested) {
      // eslint-disable-next-line unicorn/no-process-exit
      process.exit(exitRequest.exitCode);
    }
  };
}

function readAstFromCache(options, source) {
  if (!currentApp) {
    return null;
  }

  return fsReadJson(
    path.join(options.fileCachePath(), `${hash(source)}.json`)
  ).catch(() => null);
}

function hash(content) {
  return crypto
    .createHash('md5')
    .update(content)
    .digest('hex');
}

function updateFileMemoryCache(options, file) {
  if (!options.watch) {
    return;
  }

  const elmFile = elmFilesCacheForWatch.find(f => f.path === file.path);
  if (!elmFile) {
    return;
  }

  elmFile.source = file.source;
}

function exitWhenWritingToCacheHasFinished(exitCode) {
  if (filesBeingCached.size === 0 && exitRequest.requested) {
    // eslint-disable-next-line unicorn/no-process-exit
    process.exit(exitRequest.exitCode);
  }

  exitRequest = {requested: true, exitCode};
}

module.exports = {
  subscribe,
  cacheFile,
  filesBeingCached,
  readAstFromCache,
  updateFileMemoryCache,
  elmFilesCacheForWatch,
  exitWhenWritingToCacheHasFinished
};

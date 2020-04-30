const path = require('path');
const util = require('util');
const crypto = require('crypto');
const fs = require('fs-extra');
const appModel = require('./model');

const fsEnsureDir = util.promisify(fs.ensureDir);
const fsReadJson = util.promisify(fs.readJson);
const fsWriteJson = util.promisify(fs.writeJson);

let currentApp = null;
let cacheFileFunction = null;

const elmFilesCacheForWatch = [];

function subscribe(options, app) {
  cacheFileFunction = entry => cacheFile(options, entry);
  if (currentApp) {
    currentApp.ports.cacheFile.unsubscribe(cacheFileFunction);
  }

  currentApp = app;
  app.ports.cacheFile.subscribe(cacheFileFunction);
}

let hasAlreadyEnsuredDir = false;

async function cacheFile(options, {source, ast}) {
  const fileCachePath = options.fileCachePath();
  if (!hasAlreadyEnsuredDir) {
    await fsEnsureDir(fileCachePath);
    hasAlreadyEnsuredDir = true;
  }

  const sourceHash = hash(source);
  appModel.writingToFileSystemCacheStarted(sourceHash);
  return fsWriteJson(
    path.join(fileCachePath, `${sourceHash}.json`),
    ast
  ).finally(() => appModel.writingToFileSystemCacheFinished(sourceHash));
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

module.exports = {
  subscribe,
  cacheFile,
  readAstFromCache,
  updateFileMemoryCache,
  elmFilesCacheForWatch
};

const path = require('path');
const util = require('util');
const crypto = require('crypto');
const fs = require('fs-extra');

const fsEnsureDir = util.promisify(fs.ensureDir);
const fsReadJson = util.promisify(fs.readJson);
const fsWriteJson = util.promisify(fs.writeJson);

let currentApp = null;
let cacheFile = null;

const elmFilesCacheForWatch = [];

function subscribe(options, app) {
  cacheFile = cacheFile || cacheFileWithOptions(options);
  if (currentApp) {
    currentApp.ports.cacheFile.unsubscribe(cacheFile);
  }

  currentApp = app;
  app.ports.cacheFile.subscribe(cacheFile);
}

function cacheFileWithOptions(options) {
  const fileCachePath = options.fileCachePath();
  return async ({source, ast}) => {
    await fsEnsureDir(fileCachePath);
    return fsWriteJson(path.join(fileCachePath, `${hash(source)}.json`), ast);
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

module.exports = {
  subscribe,
  readAstFromCache,
  updateFileMemoryCache,
  elmFilesCacheForWatch
};

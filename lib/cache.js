const path = require('path');
const util = require('util');
const crypto = require('crypto');
const LZ4 = require('lz4');
const fs = require('fs-extra');
const appState = require('./state');

const fsEnsureDir = util.promisify(fs.ensureDir);
const fsReadFile = util.promisify(fs.readFile);
const fsWriteFile = util.promisify(fs.writeFile);

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
  return fsWriteFile(
    path.join(fileCachePath, `${sourceHash}.json`),
    compress(ast)
  ).finally(() => appState.writingToFileSystemCacheFinished(sourceHash));
}

function compress(data) {
  return LZ4.encode(JSON.stringify(data));
}

function readAstFromFSCache(options, source) {
  return (
    fsReadFile(path.join(options.fileCachePath(), `${hash(source)}.json`))
      .then(LZ4.decode)
      .then(JSON.parse)
      // Cache file is absent or could not be read
      .catch(() => null)
  );
}

function hash(content) {
  return crypto.createHash('md5').update(content).digest('hex');
}

module.exports = {
  subscribe,
  cacheFile,
  readAstFromFSCache
};

const path = require('path');
const util = require('util');
const fsExtra = require('fs-extra');
const Debug = require('./debug');
const Benchmark = require('./benchmark');
const AppState = require("./state");

const fsMkdirp = util.promisify(fsExtra.mkdirp);
const fsReadDir = util.promisify(fsExtra.readdir);
const fsWriteJson = util.promisify(fsExtra.writeJson);
const readJson = util.promisify(fsExtra.readJson);

global.elmReviewResultCache = {};

module.exports = {
  load
};

async function load(options, appHash) {
  global.saveCache = (ruleName, cacheEntry) => {
    AppState.writingToFileSystemCacheStarted(ruleName);
    saveResultFor(options, appHash, ruleName, cacheEntry)
      .catch(error => {
        Debug.log(options, `Error while trying to save result for ${ruleName}:\n${error.toString()}`)
      })
      .finally(() => {
        AppState.writingToFileSystemCacheFinished(ruleName);
      });
  };

  console.time('Load result cache');
  const cacheFolder = options.resultCachePath(appHash);
  let files = await fsReadDir(cacheFolder).catch(() => []);
  if (files.length === 0) return;
  if (options.rules) {
    files = files.filter((fileCachePath) =>
      options.rules.includes(fileCachePath.slice(0, -5))
    );
  }

  await Promise.all(
    files.map((name) =>
      readJson(path.join(cacheFolder, name)).then((entry) => {
        global.elmReviewResultCache[name.slice(0, -5)] = entry;
      })
    )
  );
  console.timeEnd('Load result cache');
}

async function writeCache(options, path, content) {
  return fsWriteJson(path, content, {spaces: options.debug ? 2 : 0});
}

async function saveResultFor(options, appHash, ruleName, cacheEntry) {
  const benchmarkText = 'Caching result of ' + ruleName;
  Benchmark.start(options, benchmarkText);
  const cacheFolder = options.resultCachePath(appHash);
  // TODO Avoid doing this too many times, maybe do this in load?
  await fsMkdirp(cacheFolder).catch(() => {});
  return writeCache(
    options,
    path.join(cacheFolder, `${ruleName}.json`),
    cacheEntry
  ).finally(() => {
    Benchmark.end(options, benchmarkText);
  });
}

const path = require('path');
const util = require('util');
const fsExtra = require('fs-extra');
const Debug = require('./debug');
const Benchmark = require('./benchmark');
const AppState = require('./state');

const fsMkdirp = util.promisify(fsExtra.mkdirp);
const fsReadDir = util.promisify(fsExtra.readdir);
const fsWriteJson = util.promisify(fsExtra.writeJson);
const readJson = util.promisify(fsExtra.readJson);

const elmReviewResultCache = {};

module.exports = {
  load
};

async function load(options, cacheFolder) {
  global.loadResultFromCache = (ruleName, ruleId) => {
    return elmReviewResultCache[key(ruleName, ruleId)];
  };

  global.saveResultToCache = (ruleName, ruleId, cacheEntry) => {
    AppState.writingToFileSystemCacheStarted(ruleName);
    saveResultFor(options, cacheFolder, ruleName, ruleId, cacheEntry)
      .catch((error) => {
        Debug.log(
          options,
          `Error while trying to save result for ${ruleName}:\n${error.toString()}`
        );
      })
      .finally(() => {
        AppState.writingToFileSystemCacheFinished(ruleName);
      });
  };

  Benchmark.start(options, 'Load result cache');
  let files = await fsReadDir(cacheFolder).catch(() => []);
  if (files.length === 0) return;
  if (options.rulesFilter) {
    files = files.filter((fileCachePath) =>
      options.rulesFilter.includes(
        fileCachePath.slice(0, fileCachePath.indexOf('-'))
      )
    );
  }

  await Promise.all(
    files.map((name) =>
      readJson(path.join(cacheFolder, name)).then((entry) => {
        elmReviewResultCache[name.slice(0, -5)] = entry;
      })
    )
  );
  Benchmark.end(options, 'Load result cache');
}

function key(ruleName, ruleId) {
  return ruleName + '-' + ruleId;
}

async function saveResultFor(
  options,
  cacheFolder,
  ruleName,
  ruleId,
  cacheEntry
) {
  const benchmarkText = `Caching result of ${ruleName} (${ruleId})`;
  Benchmark.start(options, benchmarkText);
  // TODO Avoid doing this too many times, maybe do this in load?
  await fsMkdirp(cacheFolder).catch(() => {});
  return writeCache(
    options,
    path.join(cacheFolder, `${key(ruleName, ruleId)}.json`),
    cacheEntry
  ).finally(() => {
    Benchmark.end(options, benchmarkText);
  });
}

async function writeCache(options, path, content) {
  return fsWriteJson(path, content, {spaces: options.debug ? 2 : 0});
}

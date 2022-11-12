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
    const cacheKey = key(ruleName, ruleId);
    AppState.writingToFileSystemCacheStarted(cacheKey);
    saveResultFor(options, cacheFolder, cacheKey, cacheEntry)
      .catch((error) => {
        Debug.log(
          options,
          `Error while trying to save result for ${cacheKey}:\n${error.toString()}`
        );
      })
      .finally(() => {
        AppState.writingToFileSystemCacheFinished(cacheKey);
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
      }).catch(() => {
        Debug.log(`Ignoring cache for ${name} as it could not be read`)
      })
    )
  );
  Benchmark.end(options, 'Load result cache');
}

function key(ruleName, ruleId) {
  return ruleName + '-' + ruleId;
}

async function saveResultFor(options, cacheFolder, cacheKey, cacheEntry) {
  const benchmarkText = `Caching result of ${cacheKey}`;
  // TODO Avoid doing this too many times, maybe do this in load?
  await fsMkdirp(cacheFolder).catch(() => {});
  return writeCache(
    options,
    path.join(cacheFolder, `${cacheKey}.json`),
    cacheEntry
  )
    .then(() => {
      Debug.log(benchmarkText + ' succeeded');
    })
    .catch(() => {
      Debug.log(benchmarkText + ' failed');
    });
}

async function writeCache(options, path, content) {
  return fsWriteJson(path, content, {spaces: options.debug ? 2 : 0});
}

const path = require('node:path');
const Debug = require('./debug');
const FS = require('./fs-wrapper');
const AppState = require('./state');
const Benchmark = require('./benchmark');
const ResultCacheJson = require('./result-cache-json');

/**
 * @import {Options} from "./types/options"
 * @import {Path} from "./types/path"
 */

module.exports = {
  load
};

let worker = null;
const resultCache = new Map();
const promisesToResolve = new Map();

// TODO(@jfmengels): Create an alternate version of Options used in
//   `elm-app-worker`. Depending on whether this is running in a worker or not,
//   the options will be slightly different.
/**
 * Load cache results.
 *
 * @param {Options} options
 * @param {string[]} ignoredDirs
 * @param {string[]} ignoredFiles
 * @param {Path} cacheFolder
 * @returns {Promise<void>}
 */
async function load(options, ignoredDirs, ignoredFiles, cacheFolder) {
  // TODO(@jfmengels): Make caching work for all of these combinations.
  if (
    options.debug ||
    options.directoriesToAnalyze.length > 0 ||
    ignoredDirs.length > 0 ||
    ignoredFiles.length > 0
  ) {
    globalThis.loadResultFromCache = () => null;
    globalThis.saveResultToCache = () => {};
    return;
  }

  if (!worker) {
    const {Worker} = require('node:worker_threads');
    worker = new Worker(path.resolve(__dirname, 'result-cache-worker.js'));
    worker.on('message', (cacheKey) => {
      const promise = promisesToResolve.get(cacheKey);
      if (promise) {
        Benchmark.end(options, 'Writing cache for ' + cacheKey);
        promise();
        promisesToResolve.delete(cacheKey);
      }
    });
    promisesToResolve.clear();
  }

  resultCache.clear();
  globalThis.elmJsonReplacer = ResultCacheJson.replacer;

  globalThis.loadResultFromCache = (ruleName, ruleId) => {
    return resultCache.get(key(ruleName, ruleId));
  };

  globalThis.saveResultToCache = async (ruleName, ruleId, cacheEntry) => {
    const cacheKey = key(ruleName, ruleId);

    AppState.writingToFileSystemCacheStarted(cacheKey);
    try {
      await saveToFile(options, {
        filePath: path.join(cacheFolder, `${cacheKey}.json`),
        cacheEntry,
        cacheKey
      });
      Debug.log(`Cached results of ${cacheKey}`);
    } catch (error) {
      Debug.log(
        `Error while trying to save results for ${cacheKey}:\n${error.toString()}`
      );
    } finally {
      AppState.writingToFileSystemCacheFinished(cacheKey);
    }
  };

  Benchmark.start(options, 'Load results cache');
  let files = await FS.readdir(cacheFolder).catch(() => []);
  if (files.length === 0) return;
  const {rulesFilter} = options;
  if (rulesFilter) {
    files = files.filter((fileCachePath) =>
      rulesFilter.includes(fileCachePath.slice(0, fileCachePath.indexOf('-')))
    );
  }

  await Promise.all(
    files.map((name) =>
      FS.readJsonFile(path.join(cacheFolder, name), ResultCacheJson.reviver)
        .then((entry) => {
          resultCache.set(name.slice(0, -5), entry);
        })
        .catch(() => {
          Debug.log(
            `Ignoring results cache for ${name} as it could not be read`
          );
        })
    )
  );
  Benchmark.end(options, 'Load results cache');
}

function key(ruleName, ruleId) {
  return ruleName + '-' + ruleId;
}

async function saveToFile(options, data) {
  if (worker) {
    return await new Promise((resolve) => {
      promisesToResolve.set(data.cacheKey, resolve);
      Benchmark.start(options, 'Writing cache for ' + data.cacheKey);
      worker.postMessage({
        filePath: data.filePath,
        cacheKey: data.cacheKey,
        cacheEntry: data.cacheEntry
      });
    });
  }

  await FS.mkdirp(path.dirname(data.filePath)).catch(() => {});
  return await FS.writeJson(
    data.filePath,
    data.cacheEntry,
    options.debug ? 2 : 0,
    ResultCacheJson.replacer
  );
}

/**
 * @import {Flags} from './types/flags';
 * @import {Options} from './types/options';
 * @import {Path} from './types/path';
 * @import {CacheData, CacheEntry, CacheKey, RuleId, RuleName} from './types/result-cache';
 */
const path = require('node:path');
const {Worker} = require('node:worker_threads');
const Benchmark = require('./benchmark');
const Debug = require('./debug');
const FS = require('./fs-wrapper');
const ResultCacheJson = require('./result-cache-json');
const AppState = require('./state');
const {intoError} = require('./utils');

/** @type {Worker} */
let worker;

/** @type {Map<string, CacheEntry>} */
const resultCache = new Map();

/** @type {Map<string, (value?: unknown) => unknown>} */
const promisesToResolve = new Map();

// TODO(@jfmengels): Create an alternate version of Options used in
//   `elm-app-worker`. Depending on whether this is running in a worker or not,
//   the options will be slightly different.
/**
 * Load cache results.
 *
 * @param {Options | Flags} options
 * @param {Path[]} ignoredDirs
 * @param {Path[]} ignoredFiles
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

  globalThis.loadResultFromCache = (
    /** @type {RuleName} */ ruleName,
    /** @type {RuleId} */ ruleId
  ) => {
    return resultCache.get(key(ruleName, ruleId));
  };

  globalThis.saveResultToCache = async (
    /** @type {RuleName} */ ruleName,
    /** @type {RuleId} */ ruleId,
    /** @type {CacheEntry} */ cacheEntry
  ) => {
    const cacheKey = key(ruleName, ruleId);

    AppState.writingToFileSystemCacheStarted(cacheKey);
    try {
      await saveToFile(options, {
        filePath: path.join(cacheFolder, `${cacheKey}.json`),
        cacheEntry,
        cacheKey
      });
      Debug.log(`Cached results of ${cacheKey}`, options.debug);
    } catch (err) {
      const error = intoError(err);

      Debug.log(
        `Error while trying to save results for ${cacheKey}:\n${error.toString()}`,
        options.debug
      );
    } finally {
      AppState.writingToFileSystemCacheFinished(cacheKey);
    }
  };

  Benchmark.start(options, 'Load results cache');
  /** @type {string[]} */
  let files = await FS.readdir(cacheFolder).catch(() => []);
  if (files.length === 0) return;
  const {rulesFilter} = options;
  if (rulesFilter) {
    files = files.filter((fileCachePath) =>
      rulesFilter.includes(fileCachePath.slice(0, fileCachePath.indexOf('-')))
    );
  }

  await Promise.all(
    files.map(async (/** @type {string} */ name) => {
      try {
        const entry = await FS.readJsonFile(
          path.join(cacheFolder, name),
          ResultCacheJson.reviver
        );
        resultCache.set(name.slice(0, -5), entry);
      } catch {
        Debug.log(
          `Ignoring results cache for ${name} as it could not be read`,
          options.debug
        );
      }
    })
  );
  Benchmark.end(options, 'Load results cache');
}

/**
 * @param {RuleName} ruleName
 * @param {RuleId} ruleId
 * @returns {CacheKey}
 */
function key(ruleName, ruleId) {
  return `${ruleName}-${ruleId}`;
}

/**
 * @param {Options | Flags} options
 * @param {CacheData} data
 * @returns {Promise<void>}
 */
async function saveToFile(options, data) {
  if (worker) {
    await new Promise((resolve) => {
      promisesToResolve.set(data.cacheKey, resolve);
      Benchmark.start(options, 'Writing cache for ' + data.cacheKey);
      worker.postMessage({
        filePath: data.filePath,
        cacheKey: data.cacheKey,
        cacheEntry: data.cacheEntry
      });
    });
  } else {
    await FS.mkdirp(path.dirname(data.filePath)).catch(() => {});
    await FS.writeJson(
      data.filePath,
      data.cacheEntry,
      options.debug ? 2 : 0,
      ResultCacheJson.replacer
    );
  }
}

module.exports = {
  load
};

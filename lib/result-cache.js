const path = require('path');
const Debug = require('./debug');
const FS = require('./fs-wrapper');
const AppState = require('./state');
const Benchmark = require('./benchmark');
const ResultCacheJson = require('./result-cache-json');

module.exports = {
  load
};

let worker = null;
const resultCache = new Map();
const promisesToResolve = new Map();

async function load(options, appHash) {
  // TODO Make caching work for all of these
  if (
    options.debug ||
    options.directoriesToAnalyze.length > 0 ||
    options.ignoredDirs.length > 0 ||
    options.ignoredFiles.length > 0
  ) {
    // TODO Breaking change: When we drop support for Node.js v10, use `globalThis` everywhere instead of `global`
    global.loadResultFromCache = () => null;
    global.saveResultToCache = () => {};
    return;
  }

  if (!worker) {
    try {
      // Conditional imports, because `worker_threads` is not supported by default
      // on Node v10

      const {Worker} = require('worker_threads');
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
    } catch {}
  }

  resultCache.clear();
  const cacheFolder =
    options.resultCacheFolder || options.resultCachePath(appHash);
  global.elmJsonReplacer = ResultCacheJson.replacer;

  global.loadResultFromCache = (ruleName, ruleId) => {
    return resultCache.get(key(ruleName, ruleId));
  };

  global.saveResultToCache = (ruleName, ruleId, cacheEntry) => {
    const cacheKey = key(ruleName, ruleId);

    AppState.writingToFileSystemCacheStarted(cacheKey);
    saveToFile(options, {
      filePath: path.join(cacheFolder, `${cacheKey}.json`),
      cacheEntry,
      cacheKey
    })
      .then(() => {
        Debug.log(`Cached results of ${cacheKey}`);
      })
      .catch((error) => {
        Debug.log(
          `Error while trying to save results for ${cacheKey}:\n${error.toString()}`
        );
      })
      .finally(() => {
        AppState.writingToFileSystemCacheFinished(cacheKey);
      });
  };

  Benchmark.start(options, 'Load results cache');
  let files = await FS.readdir(cacheFolder).catch(() => []);
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
    return new Promise((resolve) => {
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
  return FS.writeJson(
    data.filePath,
    data.cacheEntry,
    options.debug ? 2 : 0,
    ResultCacheJson.replacer
  );
}

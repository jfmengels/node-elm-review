const path = require('path');
const util = require('util');
const fsExtra = require('fs-extra');
const Debug = require('./debug');
const Benchmark = require('./benchmark');
const AppState = require('./state');
const {Worker} = require('worker_threads');

const fsReadDir = util.promisify(fsExtra.readdir);
const readJson = util.promisify(fsExtra.readJson);


module.exports = {
  load
};

let worker = null;
const resultCache = new Map();
const promisesToResolve = new Map();

async function load(options, cacheFolder) {
  if (!worker) {
    worker = new Worker(path.resolve(__dirname, 'result-cache-worker.js'));
    worker.on('message', cacheKey => {
      Benchmark.end(options, "Writing cache for " + cacheKey);
      promisesToResolve.get(cacheKey)();
      promisesToResolve.delete(cacheKey);
    });
  }

  promisesToResolve.clear();
  resultCache.clear();

  global.loadResultFromCache = (ruleName, ruleId) => {
    return resultCache.get(key(ruleName, ruleId));
  };

  global.saveResultToCache = (ruleName, ruleId, cacheEntry) => {
    const cacheKey = key(ruleName, ruleId);

    AppState.writingToFileSystemCacheStarted(cacheKey);
    new Promise(resolve => {
      promisesToResolve.set(cacheKey, resolve);
      Benchmark.start(options, "Writing cache for " + cacheKey);
      worker.postMessage({
        filePath: path.join(cacheFolder, `${cacheKey}.json`),
        cacheEntry: cacheEntry,
        debug: options.debug,
        cacheKey
      });
    }).then(() => {
        Debug.log(`Cached results of ${cacheKey}`);
      })
      .catch((error) => {
        Debug.log(
          options,
          `Error while trying to save results for ${cacheKey}:\n${error.toString()}`
        );
      })
      .finally(() => {
        AppState.writingToFileSystemCacheFinished(cacheKey);
      });
  };

  Benchmark.start(options, 'Load results cache');
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
      readJson(path.join(cacheFolder, name))
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

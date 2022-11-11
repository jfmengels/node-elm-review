const path = require('path');
const util = require('util');
const fsExtra = require('fs-extra');
const Debug = require('./debug');
const Benchmark = require('./benchmark');

const fsMkdirp = util.promisify(fsExtra.mkdirp);
const fsReadDir = util.promisify(fsExtra.readdir);
const fsWriteJson = util.promisify(fsExtra.writeJson);
const readJson = util.promisify(fsExtra.readJson);

global.elmReviewResultCache = {};

module.exports = {
  load,
  save
};

async function load(options, appHash) {
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

async function save(options, appHash) {
  const cacheFolder = options.resultCachePath(appHash);

  Benchmark.start('Writing result cache');
  await fsMkdirp(cacheFolder).catch(() => {});
  return Promise.all(
    Object.entries(global.elmReviewResultCache).map(([ruleName, cacheEntry]) =>
      writeCache(
        options,
        path.join(cacheFolder, `${ruleName}.json`),
        cacheEntry
      )
    )
  )
    .then(() => {
      Benchmark.end('Writing result cache');
      Debug.log('Saved result cache in ' + cacheFolder);
    })
    .catch((error) => {
      Benchmark.end('Writing result cache');
      Debug.log(
        'Failed to write result cache to the file system:\n' + error.toString()
      );
    });
}

async function writeCache(options, path, content) {
  return fsWriteJson(path, content, {spaces: options.debug ? 2 : 0});
}

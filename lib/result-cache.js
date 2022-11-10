const path = require('path');
const util = require('util');
const fsExtra = require('fs-extra');
const Debug = require('./debug');
const packageJson = require('../package.json');

const fsMkdirp = util.promisify(fsExtra.mkdirp);
const fsReadDir = util.promisify(fsExtra.readdir);
const fsWriteJson = util.promisify(fsExtra.writeJson);
const readJson=util.promisify(fsExtra.readJson)

module.exports = {
  load,
  save
};

// TODO Remove hardcoding
const namespace = 'cli';

async function load(options, appHash) {
  global.elmReviewResultCache = {};
  try {
    console.time('Load result cache');
    const dir = cacheLocation(appHash);
    let files = await fsReadDir(dir).catch(() => []);
    if (files.length === 0) return;
    if (options.rules) {
      files = files.filter(fileCachePath => options.rules.includes(fileCachePath.slice(0, -5)));
    }
    await Promise.all(files.map((name) => readJson(path.join(dir, name))
      .then((entry) => global.elmReviewResultCache[name.slice(0, -5)] = entry)
    ));
    console.timeEnd('Load result cache');
  } catch (error) {
    // TODO Check if/how we should print this.
    console.error(error.code);
    console.error(error);
  }
}

// READING

function cacheLocation(appHash) {
  return path.join(
    // TODO Check if this will always be correct, probably not
    process.cwd(),
    // ProjectToReview(),

    'elm-stuff',
    'generated-code',
    'jfmengels',
    'elm-review',
    namespace,
    packageJson.version,
    'result-cache',
    appHash
  );
}

// WRITING

async function save(options, appHash) {
  const cacheFolder = cacheLocation(appHash);

  console.time('Writing result cache');
  await fsMkdirp(cacheFolder).catch(() => {});
  return Promise.all(Object.entries(global.elmReviewResultCache)
    .map(([ruleName, cacheEntry]) => writeCache(options, path.join(cacheFolder, `${ruleName}.json`), cacheEntry)))
    .then(() => {
      console.timeEnd('Writing result cache');
      Debug.log('Saved result cache in ' + cacheFolder);
    })
    .catch((error) => {
      console.timeEnd('Writing result cache');
      Debug.log(
        'Failed to write result cache to the file system:\n' + error.toString()
      );
    });
}

async function writeCache(options, path, content) {
  return fsWriteJson(path, content, {spaces: options.debug ? 2 : 0});
}

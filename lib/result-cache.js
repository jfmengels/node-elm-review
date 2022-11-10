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
    console.time('Load rule cache');
    const dir = elmStuffRuleCacheLocation2(appHash);
    let files = await fsReadDir(dir).catch(() => []);
    if (files.length === 0) return;
    if (options.rules) {
      files = files.filter(fileCachePath => options.rules.includes(fileCachePath.slice(0, -5)));
    }
    await Promise.all(files.map((name) => readJson(path.join(dir, name))
      .then((entry) => global.elmReviewResultCache[name.slice(0, -5)] = entry)
    ));
    console.timeEnd('Load rule cache');
  } catch (error) {
    // TODO Check if/how we should print this.
    console.error(error.code);
    console.error(error);
  }
}

// READING

function elmStuffRuleCacheLocation(appHash) {
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
    `${appHash}.json`
  );
}
function elmStuffRuleCacheLocation2(appHash) {
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

function ruleCacheLocation(appHash, ruleName) {
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
    appHash,
    `${ruleName}.json`
  );
}


// WRITING

async function save(options, appHash) {
  const cacheLocation = elmStuffRuleCacheLocation(appHash);
  await fsMkdirp(elmStuffRuleCacheLocation2(appHash)).catch(() => {});

  console.time('Writing rule cache');
  return Promise.all(Object.entries(global.elmReviewResultCache)
    .map(([ruleName, cacheEntry]) => writeCache(options, ruleCacheLocation(appHash, ruleName), cacheEntry)))
    .then(() => {
      console.timeEnd('Writing rule cache');
      Debug.log('Saved rule cache at ' + cacheLocation);
    })
    .catch((error) => {
      console.timeEnd('Writing rule cache');
      Debug.log(
        'Failed to write rule cache to the file system:\n' + error.toString
      );
      // TODO Remove console.error
      console.error('Failed to write Finished writing WITH ERROR', error);
    });
}

async function writeCache(options, path, content) {
  return fsWriteJson(path, content, {spaces: options.debug ? 2 : 0});
}

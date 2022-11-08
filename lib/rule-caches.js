const path = require('path');
const util = require('util');
const fs = require('fs-extra');
const Debug = require('./debug');
const packageJson = require('../package.json');

const fsMkdirp = util.promisify(fs.mkdirp);
const fsWriteJson = util.promisify(fs.writeJson);

module.exports = {
  injectIntoGlobal,
  writeToFileSystem
};

// TODO Remove hardcoding
const namespace = 'cli';
const appHash = 'test-hash';

const elmStuffRuleCacheLocation =
  path.join(
    // TODO Check if this will always be correct, probably not
    process.cwd(),
    // ProjectToReview(),

    'elm-stuff',
    'generated-code',
    'jfmengels',
    'elm-review',
    namespace,
    packageJson.version,
    'rule-cache',
    `${appHash}.json`
  );

function injectIntoGlobal() {
  global.elmReviewRuleCaches = {};
  try {
    console.time('Load cache');
    const ruleCache = fs.readJsonSync(elmStuffRuleCacheLocation);
    global.elmReviewRuleCaches = ruleCache;
    console.timeEnd('Load cache');
  } catch (error) {
    // Cache doesn't exist yet
    if (error.code === 'ENOENT') {
      return;
    }

    // TODO Check if/how we should print this.
    console.error(error.code);
    console.error(error);
  }
}

async function writeToFileSystem() {
  await fsMkdirp(path.dirname(elmStuffRuleCacheLocation)).catch(() => {});
  return fsWriteJson(
    elmStuffRuleCacheLocation,
    global.elmReviewRuleCaches,
    {spaces: 0}
  ).then(() => {
    Debug.log('Saved rule cache at ' + elmStuffRuleCacheLocation)
  }).catch((error) => {
    Debug.log('Failed to write rule cache to the file system:\n' + error.toString);
    // TODO Remove console.error
    console.error('Failed to write Finished writing WITH ERROR', error);
  });
}

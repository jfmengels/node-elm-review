const path = require('path');
const fs = require('fs-extra');
const packageJson = require('../package.json');

module.exports = {
  injectIntoGlobal,
  writeToFileSystem
};

function injectIntoGlobal() {
  global.elmReviewRuleCaches = {};
  try {
    console.time('Load cache');
    const ruleCache = fs.readJsonSync(elmStuffRuleCacheLocation());
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

function writeToFileSystem() {
  fs.writeJson(
    elmStuffRuleCacheLocation(),
    global.elmReviewRuleCaches,
    {spaces: 0},
    (error) => {
      console.log('Finished writing', error);
    }
  );
}

// TODO Remove hardcoding
const namespace = 'CLI';
const appHash = 'test-hash';

function elmStuffRuleCacheLocation() {
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
    'review-applications',
    `${appHash}.js`
  );
}

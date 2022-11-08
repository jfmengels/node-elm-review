const path = require('path');
const util = require('util');
const {createGzip} = require('zlib');
const Stream = require('stream');
const fs = require('fs');
const fsExtra = require('fs-extra');
const Debug = require('./debug');
const packageJson = require('../package.json');

const finished = util.promisify(Stream.finished);
const fsMkdirp = util.promisify(fsExtra.mkdirp);

async function compress(ruleCaches, output) {
  const gzip = createGzip();
  const buffer = new Buffer.from(JSON.stringify(ruleCaches));
  const source = Stream.Readable.from(buffer);
  const destination = fs.createWriteStream(output);
  const stream = source.pipe(gzip).pipe(destination)
  return finished(stream)
    .catch(() => {console.log("DONE")});
}

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
    const ruleCache = fsExtra.readJsonSync(elmStuffRuleCacheLocation);
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
  return compress(
    global.elmReviewRuleCaches,
    elmStuffRuleCacheLocation
  ).then(() => {
    Debug.log('Saved rule cache at ' + elmStuffRuleCacheLocation)
  }).catch((error) => {
    Debug.log('Failed to write rule cache to the file system:\n' + error.toString);
    // TODO Remove console.error
    console.error('Failed to write Finished writing WITH ERROR', error);
  });
}

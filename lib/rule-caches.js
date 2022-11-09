const path = require('path');
const util = require('util');
const zlib = require('zlib');
const Stream = require('stream');
const fs = require('fs');
const fsExtra = require('fs-extra');
const Debug = require('./debug');
const packageJson = require('../package.json');

const finished = util.promisify(Stream.finished);
const fsMkdirp = util.promisify(fsExtra.mkdirp);
const fsWriteJson = util.promisify(fsExtra.writeJson);

const ENABLE_GZIP = process.env.GZIP == 1 || false;

module.exports = {
  injectIntoGlobal,
  writeToFileSystem
};

// TODO Remove hardcoding
const namespace = 'cli';
const appHash = 'test-hash';

function injectIntoGlobal() {
  global.elmReviewRuleCaches = {};
  try {
    console.time('Load cache');
    global.elmReviewRuleCaches = readCache();
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

// READING

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
    ENABLE_GZIP ? `${appHash}.json.gz` : `${appHash}.json`
  );

function readCache() {
  if (ENABLE_GZIP) {
    return readCacheGzipped();
  }
  return fsExtra.readJsonSync(elmStuffRuleCacheLocation);
}

function readCacheGzipped() {
  const rawCache = fsExtra.readFileSync(elmStuffRuleCacheLocation);
  // TODO This is really slow. Try to use streams instead
  // We have something in the stash for this
  return JSON.parse(zlib.unzipSync(rawCache).toString('utf8'));
}

// WRITING

async function writeToFileSystem() {
  await fsMkdirp(path.dirname(elmStuffRuleCacheLocation)).catch(() => {});
  return writeCache(
    elmStuffRuleCacheLocation,
    global.elmReviewRuleCaches
  ).then(() => {
    Debug.log('Saved rule cache at ' + elmStuffRuleCacheLocation)
  }).catch((error) => {
    Debug.log('Failed to write rule cache to the file system:\n' + error.toString);
    // TODO Remove console.error
    console.error('Failed to write Finished writing WITH ERROR', error);
  });
}

async function writeCache(path, content) {
  if (ENABLE_GZIP) {
    return writeCacheGzipped(path, content);
  }
  return fsWriteJson(path, content, {spaces: 0});
}

function writeCacheGzipped(path, content) {
  const gzip = zlib.createGzip();
  const buffer = new Buffer.from(JSON.stringify(content));
  const source = Stream.Readable.from(buffer);
  const destination = fs.createWriteStream(path);
  const stream = source.pipe(gzip).pipe(destination)
  return finished(stream)
    .catch(() => {
      Debug.log("DONE")
    });
}
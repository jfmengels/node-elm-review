const path = require('path');
const util = require('util');
const zlib = require('zlib');
const Stream = require('stream');
const fs = require('fs');
const fsExtra = require('fs-extra');
const Debug = require('./debug');
const packageJson = require('../package.json');

const zlibUnzip = util.promisify(zlib.unzip);
const finished = util.promisify(Stream.finished);
const fsMkdirp = util.promisify(fsExtra.mkdirp);
const fsReadDir = util.promisify(fsExtra.readdir);
const fsWriteJson = util.promisify(fsExtra.writeJson);
const readJson=util.promisify(fsExtra.readJson)
const readFile=util.promisify(fsExtra.readFile)

const ENABLE_GZIP = process.env.GZIP == 1 || false;

module.exports = {
  load,
  save
};

// TODO Remove hardcoding
const namespace = 'cli';

async function load(appHash) {
  global.elmReviewRuleCaches = {};
  try {
    console.time('Load rule cache');
    const dir = elmStuffRuleCacheLocation2(appHash);
    const files = await fsReadDir(dir).catch(() => []);
    if (files.length === 0) return;
    await Promise.all(files.map((name) => readCache(path.join(dir, name))
      .then((entry) => global.elmReviewRuleCaches[name.slice(0, -5)] = entry)
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
    'rule-cache',
    ENABLE_GZIP ? `${appHash}.json.gz` : `${appHash}.json`
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
    'rule-cache',
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
    'rule-cache',
    appHash,
    ENABLE_GZIP ? `${ruleName}.json.gz` : `${ruleName}.json`
  );
}

function readCache(filePath) {
  if (ENABLE_GZIP) {
    return readCacheGzipped(filePath);
  }

  return readJson(filePath);
}

async function readCacheGzipped(filePath) {
  const cacheBuffer = await readFile(elmStuffRuleCacheLocation(filePath))
    .then(zlibUnzip);
  // TODO This is really slow. Try to use streams instead
  // We have something in the stash for this
  return JSON.parse(cacheBuffer.toString('utf8'));
}

// WRITING

async function save(options, appHash) {
  const cacheLocation = elmStuffRuleCacheLocation(appHash);
  await fsMkdirp(elmStuffRuleCacheLocation2(appHash)).catch(() => {});

  console.time('Writing rule cache');
  return Promise.all(Object.entries(global.elmReviewRuleCaches)
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
  if (ENABLE_GZIP) {
    return writeCacheGzipped(path, content);
  }

  return fsWriteJson(path, content, {spaces: options.debug ? 2 : 0});
}

function writeCacheGzipped(path, content) {
  const gzip = zlib.createGzip();
  const buffer = new Buffer.from(JSON.stringify(content));
  const source = Stream.Readable.from(buffer);
  const destination = fs.createWriteStream(path);
  const stream = source.pipe(gzip).pipe(destination);
  return finished(stream);
}

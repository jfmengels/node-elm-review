const path = require('path');
const AppState = require('./state');
const Hash = require('./hash');
const Cache = require('./cache');

function subscribe(options, app) {
  AppState.subscribe(app.ports.cacheFile, ({source, ast}) =>
    // TODO Do this in a thread
    cacheFile(options, Hash.hash(source), ast)
  );
}

async function cacheFile(options, fileHash, ast) {
  return Cache.cacheJsonFile(
    path.resolve(options.fileCachePath(), `${fileHash}.json`),
    ast
  );
}

module.exports = {
  subscribe,
  cacheFile
};

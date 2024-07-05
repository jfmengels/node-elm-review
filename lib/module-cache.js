const path = require('node:path');
const AppState = require('./state');
const Hash = require('./hash');
const Cache = require('./cache');

/**
 * @import {Options} from "./types/options"
 * @import {App} from "./types/app"
 * @import {Ast} from "./types/content";
 */

/**
 * @param {Options} options
 * @param {App} app
 */
function subscribe(options, app) {
  AppState.subscribe(app.ports.cacheFile, ({source, ast}) =>
    // TODO Do this in a thread
    cacheFile(options, Hash.hash(source), ast)
  );
}

/**
 * @param {Options} options
 * @param {string} fileHash
 * @param {Ast} ast
 */
async function cacheFile(options, fileHash, ast) {
  return await Cache.cacheJsonFile(
    path.resolve(options.fileCachePath(), `${fileHash}.json`),
    ast
  );
}

module.exports = {
  subscribe,
  cacheFile
};

/**
 * @import {Options} from './types/options';
 * @import {App} from './types/app';
 * @import {Ast} from './types/content';
 */
const path = require('node:path');
const AppState = require('./state');
const Hash = require('./hash');
const Cache = require('./cache');

/**
 * @param {Options} options
 * @param {App} app
 */
function subscribe(options, app) {
  AppState.subscribe(app.ports.cacheFile, async ({source, ast}) =>
    // TODO(@jfmengels): Do this work in a thread.
    {
      await cacheFile(options, Hash.hash(source), ast);
    }
  );
}

/**
 * @param {Options} options
 * @param {string} fileHash
 * @param {Ast} ast
 */
async function cacheFile(options, fileHash, ast) {
  await Cache.cacheJsonFile(
    path.resolve(options.fileCachePath(), `${fileHash}.json`),
    ast
  );
}

module.exports = {
  subscribe,
  cacheFile
};

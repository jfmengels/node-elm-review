/*
 * Credit goes to @zwilias, from his PR here https://github.com/rtfeldman/node-test-runner/pull/356/files
 */

const path = require('path');
const util = require('util');
const crypto = require('crypto');
const fs = require('fs-extra');
const spawnAsync = require('./spawn-async');

const fsEnsureDir = util.promisify(fs.ensureDir);
const fsReadJson = util.promisify(fs.readJson);
const fsWriteJson = util.promisify(fs.writeJson);

async function get(options, elmJsonDependencies, pathToElmJson) {
  const dependencyHash = hash(JSON.stringify(elmJsonDependencies));
  const dependenciesCachePath = path.join(
    options.dependenciesCachePath(),
    `${dependencyHash}${options.localElmReviewSrc ? '-local' : ''}.json`
  );

  const result = await fsReadJson(dependenciesCachePath).catch(() => null);

  if (result) {
    return result;
  }

  return spawnAsync(
    'npx',
    [
      'elm-json',
      'solve',
      '--extra',
      'elm/json',
      'stil4m/elm-syntax',
      'elm/project-metadata-utils',

      ...(options.localElmReviewSrc
        ? ['elm-community/intdict', 'elm-community/graph']
        : []),
      '--',
      pathToElmJson
    ],
    {
      silent: true,
      env: process.env
    }
  )
    .then(JSON.parse)
    .then(dependencies => {
      fsEnsureDir(options.dependenciesCachePath()).then(() =>
        fsWriteJson(dependenciesCachePath, dependencies)
      );
      return dependencies;
    })
    .catch(handleInternetAccessError);
}

function hash(content) {
  return crypto
    .createHash('md5')
    .update(content)
    .digest('hex');
}

async function add(pathToElmJson) {
  await spawnAsync(
    'npx',
    [
      'elm-json',
      'install',
      '--yes',
      'jfmengels/elm-review@1',
      'stil4m/elm-syntax@7',
      'elm/project-metadata-utils@1',
      '--',
      pathToElmJson
    ],
    {
      silent: true,
      env: process.env
    }
  ).catch(handleInternetAccessError);

  return spawnAsync(
    'npx',
    [
      'elm-json',
      'install',
      '--test',
      '--yes',
      'elm-explorations/test@1',
      '--',
      pathToElmJson
    ],
    {
      silent: true,
      env: process.env
    }
  ).catch(handleInternetAccessError);
}

function handleInternetAccessError(error) {
  if (error && error.message && error.message.startsWith('phase: retrieve')) {
    return Promise.resolve(
      new Error(
        `I'm sorry, but it looks like you don't have Internet access at the moment.

I require it for some of my inner workings. Please connect to the Internet
and try again.`
      )
    );
  }

  return Promise.resolve(error);
}

module.exports = {
  get,
  add
};

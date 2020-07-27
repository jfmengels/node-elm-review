/*
 * Credit goes to @zwilias, from his PR here https://github.com/rtfeldman/node-test-runner/pull/356/files
 */

const path = require('path');
const util = require('util');
const crypto = require('crypto');
const fs = require('fs-extra');
const appState = require('./state');
const spawnAsync = require('./spawn-async');
const errorMessage = require('./error-message');

module.exports = {
  get,
  add
};

const fsEnsureDir = util.promisify(fs.ensureDir);
const fsReadJson = util.promisify(fs.readJson);
const fsWriteJson = util.promisify(fs.writeJson);

// GET

async function get(options, elmJsonDependencies, pathToElmJson) {
  const dependencyHash = hash(JSON.stringify(elmJsonDependencies));
  // TODO Move this to options
  const dependenciesCachePath = path.join(
    options.dependenciesCachePath(),
    `${dependencyHash}${options.localElmReviewSrc ? '-local' : ''}.json`
  );

  const result = await fsReadJson(dependenciesCachePath).catch(() => null);

  if (result) {
    return result;
  }

  return spawnElmJson([
    'solve',
    '--extra',
    'elm/json',
    'stil4m/elm-syntax',
    'elm/project-metadata-utils',
    '--',
    pathToElmJson
  ])
    .then(JSON.parse)
    .then((dependencies) => {
      if (options.localElmReviewSrc) {
        delete dependencies.direct['jfmengels/elm-review'];
        delete dependencies.indirect['jfmengels/elm-review'];
      }

      fsEnsureDir(options.dependenciesCachePath()).then(() =>
        fsWriteJson(dependenciesCachePath, dependencies)
      );
      return dependencies;
    })
    .catch(handleInternetAccessError);
}

function hash(content) {
  return crypto.createHash('md5').update(content).digest('hex');
}

// ADD

async function add(pathToElmJson, additionalDeps) {
  await spawnElmJson([
    'install',
    '--yes',
    'elm/core@1',
    'elm/json@1',
    'jfmengels/elm-review@2',
    'stil4m/elm-syntax@7',
    'elm/project-metadata-utils@1',
    ...additionalDeps,
    '--',
    pathToElmJson
  ]).catch(handleInternetAccessError);

  return spawnElmJson([
    'install',
    '--test',
    '--yes',
    'elm-explorations/test@1',
    '--',
    pathToElmJson
  ]).catch(handleInternetAccessError);
}

// SPAWNING

function spawnElmJson(args) {
  if (appState.useElmJsonThroughNpx()) {
    return spawnThroughNpx(args).catch((error) => {
      appState.elmJsonIsNotAvailableThroughNpx();
      if (error.code !== 'ENOENT') {
        throw error;
      }

      return spawnGlobalElmJson(args);
    });
  }

  return spawnGlobalElmJson(args);
}

function spawnThroughNpx(args) {
  return spawnElmJsonAsync('npx', ['--no-install', 'elm-json', ...args]);
}

function spawnGlobalElmJson(args) {
  return spawnElmJsonAsync('elm-json', args);
}

function spawnElmJsonAsync(command, args) {
  return spawnAsync(command, args, {
    silent: true,
    env: process.env
  });
}

function handleInternetAccessError(error) {
  if (error && error.message && error.message.startsWith('phase: retrieve')) {
    return Promise.reject(
      new errorMessage.CustomError(
        /* eslint-disable prettier/prettier */
'MISSING INTERNET ACCESS',
`I’m sorry, but it looks like you don’t have Internet access at the moment.
I require it for some of my inner workings.

Please connect to the Internet and try again. After that, as long as you don’t
change your configuration or remove \`elm-stuff/\`, you should be able to go
offline again.`
          /* eslint-enable prettier/prettier */
      )
    );
  }

  return Promise.reject(error);
}

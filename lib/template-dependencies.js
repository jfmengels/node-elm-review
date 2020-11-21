/*
 * Credit goes to @zwilias, from his PR here https://github.com/rtfeldman/node-test-runner/pull/356/files
 */

const path = require('path');
const util = require('util');
const crypto = require('crypto');
const fs = require('fs-extra');
const spawnAsync = require('cross-spawn-promise');
const ErrorMessage = require('./error-message');
const getExecutable = require('elm-tooling/getExecutable');

module.exports = {
  get,
  add,
  update
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

  return spawnElmJsonAsync([
    'solve',
    '--extra',
    'elm/json',
    'stil4m/elm-syntax',
    'elm/project-metadata-utils',
    'MartinSStewart/elm-serialize',
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

async function add(pathToElmJson) {
  await spawnElmJsonAsync([
    'install',
    '--yes',
    'elm/core@1',
    'elm/json@1',
    'jfmengels/elm-review@2',
    'stil4m/elm-syntax@7',
    'elm/project-metadata-utils@1',
    '--',
    pathToElmJson
  ]).catch(handleInternetAccessError);

  return spawnElmJsonAsync([
    'install',
    '--test',
    '--yes',
    'elm-explorations/test@1',
    '--',
    pathToElmJson
  ]).catch(handleInternetAccessError);
}

// UPDATE

async function update(options, pathToElmJson) {
  await spawnElmJsonAsync(['upgrade', '--yes', pathToElmJson]).catch(
    handleInternetAccessError
  );

  const elmJson = await fsReadJson(pathToElmJson);
  if (elmJson.type === 'application') {
    delete elmJson.dependencies.indirect['elm-explorations/test'];
  }

  if (options.subcommand === 'init') {
    await fsWriteJson(pathToElmJson, elmJson, {spaces: 4});
  }

  return elmJson;
}

// SPAWNING

let elmJsonPromise;

function spawnElmJsonAsync(args) {
  if (elmJsonPromise === undefined) {
    elmJsonPromise = getExecutable({
      name: 'elm-json',
      version: '^0.2.8',
      onProgress: (percentage) => {
        const message = `Downloading elm-json... ${Math.round(
          percentage * 100
        )}%`;
        process.stderr.write(
          percentage >= 1
            ? `${'Working...'.padEnd(message.length, ' ')}\r`
            : `${message}\r`
        );
      }
    }).catch((error) => {
      throw new ErrorMessage.CustomError(
        /* eslint-disable prettier/prettier */
'PROBLEM INSTALLING elm-json',
`I need a tool called elm-json for some of my inner workings,
but there was some trouble installing it. This is what we know:

${error.message}`
        /* eslint-enable prettier/prettier */
      );
    });
  }

  return elmJsonPromise.then((elmJsonCLI) =>
    spawnAsync(elmJsonCLI, args, {
      silent: true,
      env: process.env
    })
  );
}

function handleInternetAccessError(error) {
  if (error && error.message && error.message.startsWith('phase: retrieve')) {
    return Promise.reject(
      new ErrorMessage.CustomError(
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

/*
 * Credit goes to @zwilias, from his PR here https://github.com/rtfeldman/node-test-runner/pull/356/files
 */

const path = require('path');
const util = require('util');
const crypto = require('crypto');
const fs = require('fs-extra');
const spawnAsync = require('cross-spawn');
const ErrorMessage = require('./error-message');
const getExecutable = require('elm-tooling/getExecutable');

module.exports = {
  get,
  add,
  update,
  addElmSyntax
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

  return spawnElmJsonAsync(options, [
    'solve',
    '--extra',
    'elm/json@1',
    'stil4m/elm-syntax@7',
    'elm/project-metadata-utils@1',
    'MartinSStewart/elm-serialize@1',
    '--',
    pathToElmJson
  ])
    .catch((error) => {
      throw new ErrorMessage.CustomError(
        'CONFIGURATION COMPILATION ERROR',
        `I encountered a problem when solving dependencies:

${formatElmJsonError(error, options)}`,
        null
      );
    })
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

function formatElmJsonError(error, options) {
  if (error.stderr === undefined) {
    return error.message;
  }

  const stderrMessage = error.stderr.toString().trim();
  const exec = /^([^]+\n)?--\s([A-Z ]+)\s-*\n\n([^]+)$/.exec(stderrMessage);
  if (exec === null) {
    return `${error.message}\n\n${
      stderrMessage === '' ? '(empty stderr)' : stderrMessage
    }`;
  }

  const [, before, title, message] = exec;
  return ErrorMessage.formatHuman(
    options.debug,
    new ErrorMessage.CustomError(
      title,
      before === undefined ? message : `${message}\n\n${before}`
    )
  );
}

function hash(content) {
  return crypto.createHash('md5').update(content).digest('hex');
}

// ADD ELM-SYNTAX

async function addElmSyntax(options, pathToElmJson, elmSyntaxVersion) {
  return spawnElmJsonAsync(options, [
    'solve',
    '--extra',
    `stil4m/elm-syntax@${elmSyntaxVersion}`,
    '--',
    pathToElmJson
  ])
    .catch((error) => {
      throw new ErrorMessage.CustomError(
        'CONFIGURATION COMPILATION ERROR',
        `I encountered a problem when solving dependencies for creating the parser application:

${formatElmJsonError(error, options)}`,
        null
      );
    })
    .then(JSON.parse)
    .catch(handleInternetAccessError);
}

// ADD

async function add(options, pathToElmJson) {
  await spawnElmJsonAsync(options, [
    'install',
    '--yes',
    'elm/core@1',
    'jfmengels/elm-review@2',
    'stil4m/elm-syntax@7',
    '--',
    pathToElmJson
  ]).catch(handleInternetAccessError);

  return spawnElmJsonAsync(options, [
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
  await spawnElmJsonAsync(options, ['upgrade', '--yes', pathToElmJson]).catch(
    handleInternetAccessError
  );

  const elmJson = await fsReadJson(pathToElmJson);
  if (options.subcommand === 'init') {
    await fsWriteJson(pathToElmJson, elmJson, {spaces: 4});
  }

  return elmJson;
}

// SPAWNING

let elmJsonPromise;

function spawnElmJsonAsync(options, args) {
  if (elmJsonPromise === undefined) {
    elmJsonPromise = getExecutable({
      name: 'elm-json',
      version: '^0.2.10',
      onProgress: (percentage) => {
        const message = `Downloading elm-json... ${Math.round(
          percentage * 100
        )}%`;

        if (options.report !== 'json' || options.debug) {
          process.stderr.write(
            percentage >= 1
              ? `${'Working...'.padEnd(message.length, ' ')}\r`
              : `${message}\r`
          );
        }
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

  return elmJsonPromise.then(
    (elmJsonCLI) =>
      new Promise((resolve, reject) => {
        const child = spawnAsync(elmJsonCLI, args, {
          silent: true,
          env: process.env
        });
        let stdout = '';
        let stderr = '';

        child.on('error', reject);

        child.stdout.on('data', (chunk) => {
          stdout += chunk.toString();
        });

        child.stderr.on('data', (chunk) => {
          stderr += chunk.toString();
        });

        child.on('close', (code, signal) => {
          if (code === 0) {
            resolve(stdout);
          } else {
            const error = new Error(
              `elm-json exited with ${exitReason(code, signal)}`
            );
            error.stderr = stderr;
            reject(error);
          }
        });
      })
  );
}

function exitReason(code, signal) {
  if (code !== null) {
    return `exit code ${code}`;
  }

  if (signal !== null) {
    return `signal ${signal}`;
  }

  return 'unknown reason';
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

/*
 * Credit goes to @zwilias, from his PR here https://github.com/rtfeldman/node-test-runner/pull/356/files
 */

const spawnAsync = require('cross-spawn');
const Hash = require('./hash');
const Cache = require('./cache');
const FS = require('./fs-wrapper');
const ErrorMessage = require('./error-message');
const getExecutable = require('elm-tooling/getExecutable');
const DependencyProvider = require('./dependency-provider');

let dependencyProvider;

/**
 * @typedef { import("./types/options").Options } Options
 * @typedef { import("./types/template-dependencies").TemplateDependenciesError } TemplateDependenciesError
 */

module.exports = {
  get,
  add,
  update,
  addElmSyntax
};

// GET

async function get(options, elmJson) {
  const dependencyHash = Hash.hash(JSON.stringify(elmJson.dependencies));
  const cacheKey = `${dependencyHash}${
    options.localElmReviewSrc ? '-local' : ''
  }`;
  return Cache.getOrCompute(options.dependenciesCachePath(), cacheKey, () =>
    computeDependencies(options, elmJson)
  );
}

function computeDependencies(options, elmJson) {
  const extra = {
    'elm/json': '1.0.0 <= v < 2.0.0',
    'stil4m/elm-syntax': '7.0.0 <= v < 8.0.0',
    'elm/project-metadata-utils': '1.0.0 <= v < 2.0.0'
  };

  const dependencies = solve(
    options,
    elmJson['elm-version'],
    JSON.stringify(elmJson),
    extra
  );
  if (options.localElmReviewSrc) {
    delete dependencies.direct['jfmengels/elm-review'];
    delete dependencies.indirect['jfmengels/elm-review'];
  }

  return dependencies;
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

// ADD ELM-SYNTAX

function addElmSyntax(options, elmVersion, elmSyntaxVersion) {
  const elmJson = `{
    "type": "application",
    "source-directories": [
        "src",
        "../ast-codec/src"
    ],
    "elm-version": "0.19.1",
    "dependencies": {
        "direct": {
            "elm/core": "1.0.5",
            "elm/json": "1.1.3"
        },
        "indirect": {}
    },
    "test-dependencies": {
        "direct": {},
        "indirect": {}
    }
}`;
  const extra = {
    'stil4m/elm-syntax': `${elmSyntaxVersion} <= v < ${nextPatchVersion(
      elmSyntaxVersion
    )}`
  };

  return solve(options, elmVersion, elmJson, extra);
}

function solve(options, elmVersion, elmJson, extra) {
  dependencyProvider = dependencyProvider || new DependencyProvider(elmVersion);

  try {
    return JSON.parse(dependencyProvider.solveOffline(elmJson, extra));
  } catch (error) {
    if (options.offline) {
      throw error;
    }
    return JSON.parse(dependencyProvider.solveOnline(elmJson, extra));
  }
}

function nextPatchVersion(version) {
  const [major, minor, patch] = version.split('.');
  return `${major}.${minor}.${parseInt(patch, 10) + 1}`;
}

// ADD

async function add(options, pathToElmJson) {
  await spawnElmJsonAsync(
    options,
    [
      'install',
      '--yes',
      'elm/core@1',
      'jfmengels/elm-review@2',
      'stil4m/elm-syntax@7',
      '--',
      pathToElmJson
    ],
    (error) => {
      throw new ErrorMessage.CustomError(
        'CONFIGURATION COMPILATION ERROR',
        `I encountered a problem when adding base dependencies:

${formatElmJsonError(error, options)}`,
        null
      );
    }
  );

  return spawnElmJsonAsync(
    options,
    [
      'install',
      '--test',
      '--yes',
      'elm-explorations/test@2',
      '--',
      pathToElmJson
    ],
    (error) => {
      throw new ErrorMessage.CustomError(
        'CONFIGURATION COMPILATION ERROR',
        `I encountered a problem when adding test dependencies:

${formatElmJsonError(error, options)}`,
        null
      );
    }
  );
}

// UPDATE

async function update(options, pathToElmJson) {
  await spawnElmJsonAsync(
    options,
    ['upgrade', '--yes', pathToElmJson],
    (error) => {
      throw new ErrorMessage.CustomError(
        'CONFIGURATION COMPILATION ERROR',
        `I encountered a problem when attempting to update the dependencies:

${formatElmJsonError(error, options)}`,
        null
      );
    }
  );

  const elmJson = await FS.readJsonFile(pathToElmJson);
  if (options.subcommand === 'init') {
    await FS.writeJson(pathToElmJson, elmJson, 4);
  }

  return elmJson;
}

// SPAWNING

let elmJsonPromise;

/**
 * Run elm-json
 * @param {Options} options
 * @param {string[]} args
 * @param {(Error) => Error} onError
 * @returns {Promise<string>}
 */
function spawnElmJsonAsync(options, args, onError) {
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
        // prettier-ignore
        'PROBLEM INSTALLING elm-json',
        // prettier-ignore
        `I need a tool called elm-json for some of my inner workings,
but there was some trouble installing it. This is what we know:

${error.message}`
      );
    });
  }

  return elmJsonPromise
    .then(
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
              /** @type {TemplateDependenciesError} */
              const error = new Error(
                `elm-json exited with ${exitReason(
                  code,
                  signal
                )}\n\n${stdout}\n\n${stderr}`
              );
              error.stderr = stderr;
              reject(error);
            }
          });
        })
    )
    .catch((error) => {
      if (
        error &&
        error.message &&
        error.message.startsWith('phase: retrieve')
      ) {
        return Promise.reject(
          new ErrorMessage.CustomError(
            // prettier-ignore
            'MISSING INTERNET ACCESS',
            // prettier-ignore
            `I’m sorry, but it looks like you don’t have Internet access at the moment.
I require it for some of my inner workings.

Please connect to the Internet and try again. After that, as long as you don’t
change your configuration or remove \`elm-stuff/\`, you should be able to go
offline again.`
          )
        );
      }

      return Promise.reject(onError(error));
    });
}

/**
 * @param {number | null} code
 * @param {string | null} signal
 * @returns {string}
 */
function exitReason(code, signal) {
  if (code !== null) {
    return `exit code ${code}`;
  }

  if (signal !== null) {
    return `signal ${signal}`;
  }

  return 'unknown reason';
}

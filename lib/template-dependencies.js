/*
 * Credit goes to @zwilias, from his PR here https://github.com/rtfeldman/node-test-runner/pull/356/files
 */

const Hash = require('./hash');
const Cache = require('./cache');
const FS = require('./fs-wrapper');
const MinVersion = require("./min-version");
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
    extra,
    false
  );
  if (options.localElmReviewSrc) {
    delete dependencies.direct['jfmengels/elm-review'];
    delete dependencies.indirect['jfmengels/elm-review'];
  }

  return dependencies;
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

  return solve(options, elmVersion, elmJson, extra, false);
}

function solve(options, elmVersion, elmJson, extra, useTest /*: boolean */) {
  dependencyProvider = dependencyProvider || new DependencyProvider(elmVersion);

  try {
    return JSON.parse(dependencyProvider.solveOffline(elmJson, useTest, extra));
  } catch (error) {
    if (options.offline) {
      throw error;
    }
    return JSON.parse(dependencyProvider.solveOnline(elmJson, useTest, extra));
  }
}

function nextPatchVersion(version) {
  const [major, minor, patch] = version.split('.');
  return `${major}.${minor}.${parseInt(patch, 10) + 1}`;
}

// ADD

function add(options, elmJson) {
  const extra = {
    'elm/core': '1.0.0 <= v < 2.0.0',
    'stil4m/elm-syntax': '7.0.0 <= v < 8.0.0',
    'jfmengels/elm-review': MinVersion.supportedRange
  };
  const extraTestDependencies = {
    'elm-explorations/test': '2.0.0 <= v < 3.0.0'
  };

  elmJson.dependencies = solve(
    options,
    elmJson['elm-version'],
    JSON.stringify(elmJson),
    extra,
    false
  );

  elmJson.dependencies = solve(
    options,
    elmJson['elm-version'],
    JSON.stringify(elmJson),
    extraTestDependencies,
    true
  );

  dependencyProvider.tearDown();

  return elmJson;
}

// UPDATE

async function update(options, pathToElmJson, elmJson) {
  const extra = {
    'stil4m/elm-syntax': '7.0.0 <= v < 8.0.0',
    'jfmengels/elm-review': MinVersion.supportedRange
  };

  elmJson.dependencies = solve(
      options,
      elmJson['elm-version'],
      JSON.stringify(elmJson),
      extra,
      false
  );

  if (options.subcommand === 'init') {
    dependencyProvider.tearDown();
    await FS.writeJson(pathToElmJson, elmJson, 4);
  }

  return elmJson;
}
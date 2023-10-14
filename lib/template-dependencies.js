/*
 * Credit goes to @zwilias, from his PR here https://github.com/rtfeldman/node-test-runner/pull/356/files
 */

const Hash = require('./hash');
const Cache = require('./cache');
const FS = require('./fs-wrapper');
const MinVersion = require('./min-version');
const DependencyProvider = require('./dependency-provider');

let dependencyProvider = null;

/**
 * @typedef { import("./types/options").Options } Options
 * @typedef { import("./types/template-dependencies").TemplateDependenciesError } TemplateDependenciesError
 */

module.exports = {
  get,
  createNewReviewElmJson,
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

  return solve(options, elmVersion, elmJson, extra, false, false);
}

function solve(
  options,
  elmVersion,
  elmJson,
  extra,
  onlineFirst /*: boolean */
) {
  dependencyProvider = dependencyProvider || new DependencyProvider(elmVersion);

  try {
    return JSON.parse(
      onlineFirst && !options.offline
        ? dependencyProvider.solveOnline(elmJson, extra)
        : dependencyProvider.solveOffline(elmJson, extra)
    );
  } catch (error) {
    if (options.offline) {
      throw error;
    }

    return JSON.parse(
      onlineFirst
        ? dependencyProvider.solveOffline(elmJson, extra)
        : dependencyProvider.solveOnline(elmJson, extra)
    );
  }
}

function nextMajorVersion(version) {
  const [major] = version.split('.');
  return `${parseInt(major, 10) + 1}.0.0`;
}

function nextPatchVersion(version) {
  const [major, minor, patch] = version.split('.');
  return `${major}.${minor}.${parseInt(patch, 10) + 1}`;
}

// ADD

function createNewReviewElmJson(options, elmVersion) {
  const elmJson = {
    type: 'application',
    'source-directories': ['src'],
    'elm-version': elmVersion || '0.19.1',
    dependencies: {
      direct: {},
      indirect: {}
    },
    'test-dependencies': {
      direct: {},
      indirect: {}
    }
  };

  const testDependencies = solve(
    options,
    elmJson['elm-version'],
    JSON.stringify(elmJson),
    {
      'elm/core': '1.0.0 <= v < 2.0.0',
      'elm-explorations/test': '2.0.0 <= v < 3.0.0'
    },
    false
  );

  elmJson.dependencies = solve(
    options,
    elmJson['elm-version'],
    JSON.stringify(elmJson),
    {
      'elm/core': '1.0.0 <= v < 2.0.0',
      'stil4m/elm-syntax': '7.0.0 <= v < 8.0.0',
      'jfmengels/elm-review': MinVersion.supportedRange
    },
    true
  );

  elmJson['test-dependencies'].direct = filterOutDuplicateDependencies(
    testDependencies.direct,
    elmJson.dependencies.direct,
    {}
  );
  elmJson['test-dependencies'].indirect = filterOutDuplicateDependencies(
    testDependencies.indirect,
    elmJson.dependencies.indirect
  );

  teardownDependenciesProvider();

  return elmJson;
}

function filterOutDuplicateDependencies(testDependencies, regularDependencies) {
  return Object.fromEntries(
    Object.entries(testDependencies).filter(
      ([pkg, _]) => !regularDependencies[pkg]
    )
  );
}

// UPDATE

async function update(options, pathToElmJson, elmJson) {
  const extra = {
    'stil4m/elm-syntax': '7.0.0 <= v < 8.0.0',
    'jfmengels/elm-review': MinVersion.supportedRange
  };

  Object.entries(elmJson.dependencies.direct).forEach(([pkg, version]) => {
    extra[pkg] = `${version} <= v < ${nextMajorVersion(version)}`;
  });

  delete elmJson.dependencies.direct['jfmengels/elm-review'];
  delete elmJson.dependencies.direct['stil4m/elm-syntax'];

  elmJson.dependencies = solve(
    options,
    elmJson['elm-version'],
    JSON.stringify({...elmJson, dependencies: {direct: {}, indirect: {}}}),
    extra,
    true
  );

  if (options.subcommand === 'init' || options.subcommand === 'new-package') {
    teardownDependenciesProvider();
  }

  if (options.subcommand === 'init') {
    await FS.writeJson(pathToElmJson, elmJson, 4);
  }

  return elmJson;
}

function teardownDependenciesProvider() {
  dependencyProvider.tearDown();
  dependencyProvider = null;
}

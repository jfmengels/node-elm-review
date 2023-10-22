/*
 * Credit goes to @zwilias, from his PR here https://github.com/rtfeldman/node-test-runner/pull/356/files
 */

const MinVersion = require('./min-version');
const DependencyProvider = require('./dependency-provider');

/** @type {DependencyProvider | null} */
let dependencyProvider = null;

/**
 * @typedef { import("./types/options").Options } Options
 * @typedef { import("./types/elm-version").ElmVersion } ElmVersion
 * @typedef { import("./types/build").ReviewElmJson } ReviewElmJson
 * @typedef { import("./types/build").ApplicationDependencies } ApplicationDependencies
 * @typedef { import("./types/template-dependencies").TemplateDependenciesError } TemplateDependenciesError
 */

module.exports = {
  addRequiredDependencies,
  createNewReviewElmJson,
  update,
  addElmSyntax
};

/** Add required dependencies for the application elm.json file.
 *
 * @param {Options} options
 * @param {ReviewElmJson} elmJson
 * @return {ApplicationDependencies}
 */
function addRequiredDependencies(options, elmJson) {
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

/** Compute the dependencies if we were to replace the version of `stil4m/elm-syntax` with the given one.
 *
 * @param {Options} options
 * @param {ElmVersion} elmVersion
 * @param {ElmVersion} elmSyntaxVersion
 * @return {ApplicationDependencies}
 */
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

  // We want to use this exact version of `stil4m/elm-syntax`.
  const extra = {
    'stil4m/elm-syntax': `${elmSyntaxVersion} <= v < ${nextPatchVersion(
      elmSyntaxVersion
    )}`
  };

  return solve(options, elmVersion, elmJson, extra, false);
}

/**
 * @param {Options} options
 * @param {ElmVersion} elmVersion
 * @param {string} elmJson
 * @param {Record<string, string>}extra
 * @param {boolean} onlineFirst
 * @return {ApplicationDependencies}
 */
function solve(options, elmVersion, elmJson, extra, onlineFirst) {
  dependencyProvider = dependencyProvider || new DependencyProvider();

  try {
    return JSON.parse(
      onlineFirst && !options.offline
        ? dependencyProvider.solveOnline(options, elmVersion, elmJson, extra)
        : dependencyProvider.solveOffline(options, elmVersion, elmJson, extra)
    );
  } catch (error) {
    if (options.offline) {
      throw error;
    }

    return JSON.parse(
      onlineFirst
        ? dependencyProvider.solveOffline(options, elmVersion, elmJson, extra)
        : dependencyProvider.solveOnline(options, elmVersion, elmJson, extra)
    );
  }
}

/** Returns the next major version.
 * Ex: 2.13.0 -> 3.0.0
 *
 * @param {ElmVersion} version
 * @return {ElmVersion}
 */
function nextMajorVersion(version) {
  const [major] = version.split('.');
  return `${parseInt(major, 10) + 1}.0.0`;
}

/** Returns the next patch version.
 * Ex: 2.13.0 -> 2.13.1
 *
 * @param {ElmVersion} version
 * @return {ElmVersion}
 */
function nextPatchVersion(version) {
  const [major, minor, patch] = version.split('.');
  return `${major}.${minor}.${parseInt(patch, 10) + 1}`;
}

/** Create a new elm.json with basic `elm-review` dependencies.
 *
 * @param {Options} options
 * @param {ElmVersion} elmVersion
 * @return {ReviewElmJson}
 */
function createNewReviewElmJson(options, elmVersion) {
  /** @type {ReviewElmJson} */
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
    elmJson.dependencies.direct
  );
  elmJson['test-dependencies'].indirect = filterOutDuplicateDependencies(
    testDependencies.indirect,
    elmJson.dependencies.indirect
  );

  teardownDependenciesProvider();

  return elmJson;
}

/** Filter out test-dependencies that are already in the regular dependencies.
 *
 * @param {Record<string, string>} testDependencies
 * @param {Record<string, string>} regularDependencies
 * @return {Record<string, string>}
 */
function filterOutDuplicateDependencies(testDependencies, regularDependencies) {
  return Object.fromEntries(
    Object.entries(testDependencies).filter(
      ([pkg, _]) => !regularDependencies[pkg]
    )
  );
}

/** Update versions of dependencies to their latest (compatible) version.
 *
 * @param {Options} options
 * @param {ReviewElmJson} elmJson
 * @return {Promise<ReviewElmJson>}
 */
async function update(options, elmJson) {
  const extra = {
    'stil4m/elm-syntax': '7.0.0 <= v < 8.0.0',
    'jfmengels/elm-review': MinVersion.supportedRange
  };

  Object.entries(elmJson.dependencies.direct).forEach(([pkg, version]) => {
    extra[pkg] = `${version} <= v < ${nextMajorVersion(version)}`;
  });

  delete elmJson.dependencies.direct['jfmengels/elm-review'];
  delete elmJson.dependencies.direct['stil4m/elm-syntax'];

  // TODO Upgrade test dependencies too for init or new-package
  elmJson.dependencies = solve(
    options,
    elmJson['elm-version'],
    JSON.stringify({...elmJson, dependencies: {direct: {}, indirect: {}}}),
    extra,
    true
  );

  teardownDependenciesProvider();

  return elmJson;
}

function teardownDependenciesProvider() {
  if (dependencyProvider) {
    dependencyProvider.tearDown();
    dependencyProvider = null;
  }
}

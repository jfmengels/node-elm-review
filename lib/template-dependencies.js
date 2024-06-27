const path = require('node:path');
const chalk = require('chalk');
const MinVersion = require('./min-version');
const ErrorMessage = require('./error-message');
const DependencyProvider = require('./dependency-provider');
const FS = require('./fs-wrapper');

/** @type {DependencyProvider | null} */
let dependencyProvider = null;

const parseElmFolder = path.join(__dirname, '../parseElm');

/**
 * @import {Options} from "./types/options"
 * @import {ElmVersion} from "./types/elm-version"
 * @import {ApplicationElmJson, ApplicationDependencies} from "./types/content"
 */

module.exports = {
  addRequiredDependencies,
  createNewReviewElmJson,
  update,
  addElmSyntax
};

/**
 * Add required dependencies for the application elm.json file.
 *
 * @param {Options} options
 * @param {ApplicationElmJson} elmJson
 * @returns {ApplicationDependencies}
 */
function addRequiredDependencies(options, elmJson) {
  const extra = {
    'elm/json': '1.0.0 <= v < 2.0.0',
    'stil4m/elm-syntax': '7.0.0 <= v < 8.0.0',
    'elm/project-metadata-utils': '1.0.0 <= v < 2.0.0'
  };

  try {
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
  } catch (error) {
    throw new ErrorMessage.CustomError(
      'CONFIGURATION COMPILATION ERROR',
      `I encountered a problem when solving dependencies for creating the parser application:

${error.toString().replace(/^Error: /, '')}`,
      null
    );
  }
}

// ADD ELM-SYNTAX

/**
 * Compute the dependencies if we were to replace the version of `stil4m/elm-syntax` with the given one.
 *
 * @param {Options} options
 * @param {ElmVersion} elmVersion
 * @param {ElmVersion} elmSyntaxVersion
 * @returns {Promise<ApplicationElmJson>}
 */
async function addElmSyntax(options, elmVersion, elmSyntaxVersion) {
  const elmJsonPath = path.resolve(parseElmFolder, 'elm.json');
  const elmJson = /** @type {ApplicationElmJson} */ (
    await FS.readJsonFile(elmJsonPath).catch((error) => {
      if (error.code === 'ENOENT') {
        throw new ErrorMessage.CustomError(
          // prettier-ignore
          'UNEXPECTED INTERNAL ERROR',
          // prettier-ignore
          `I was expecting to find the "parseElm" project at ${chalk.cyan(elmJsonPath)} but could not find it.

Please open an issue at the following link:
https://github.com/jfmengels/node-elm-review/issues/new
`,
          options.elmJsonPath
        );
      }

      throw error;
    })
  );

  elmJson['elm-version'] = elmVersion;
  delete elmJson.dependencies.direct['stil4m/elm-syntax'];
  elmJson.dependencies = solve(
    options,
    elmVersion,
    JSON.stringify(elmJson),
    {
      'stil4m/elm-syntax': `${elmSyntaxVersion} <= v < ${nextPatchVersion(
        elmSyntaxVersion
      )}`
    },
    false
  );
  return elmJson;
}

/**
 * @param {Options} options
 * @param {ElmVersion} elmVersion
 * @param {string} elmJson
 * @param {Record<string, string>}extra
 * @param {boolean} onlineFirst
 * @returns {ApplicationDependencies}
 */
function solve(options, elmVersion, elmJson, extra, onlineFirst) {
  if (dependencyProvider === null) {
    dependencyProvider = new DependencyProvider();
  }

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

/**
 * @param {ElmVersion} version
 * @returns {ElmVersion} the next major version.
 *   Ex: 2.13.0 -> 3.0.0
 */
function nextMajorVersion(version) {
  const [major] = version.split('.');
  return `${Number.parseInt(major, 10) + 1}.0.0`;
}

/**
 * @param {ElmVersion} version
 * @returns {ElmVersion} the next patch version.
 *   Ex: 2.13.0 -> 2.13.1
 */
function nextPatchVersion(version) {
  const [major, minor, patch] = version.split('.');
  return `${major}.${minor}.${Number.parseInt(patch, 10) + 1}`;
}

/**
 * Create a new elm.json with basic `elm-review` dependencies.
 *
 * @param {Options} options
 * @param {ElmVersion} elmVersion
 * @returns {ApplicationElmJson}
 */
function createNewReviewElmJson(options, elmVersion) {
  /** @type {ApplicationElmJson} */
  const elmJson = {
    type: 'application',
    'source-directories': ['src'],
    'elm-version': elmVersion,
    dependencies: {
      direct: {},
      indirect: {}
    },
    'test-dependencies': {
      direct: {},
      indirect: {}
    }
  };
  const stringifiedElmJson = JSON.stringify(elmJson);

  elmJson.dependencies = solve(
    options,
    elmVersion,
    stringifiedElmJson,
    {
      'elm/core': '1.0.0 <= v < 2.0.0',
      'stil4m/elm-syntax': '7.0.0 <= v < 8.0.0',
      'jfmengels/elm-review': MinVersion.supportedRange
    },
    true
  );

  const testDependencies = solve(
    options,
    elmVersion,
    stringifiedElmJson,
    {
      'elm/core': '1.0.0 <= v < 2.0.0',
      'elm-explorations/test': '2.0.0 <= v < 3.0.0'
    },
    false
  );

  elmJson['test-dependencies'] = filterOutDuplicateDependencies(
    testDependencies,
    elmJson.dependencies
  );

  teardownDependenciesProvider();

  return elmJson;
}

/**
 * Filter out test-dependencies that are already in the regular dependencies.
 *
 * @param {{direct: Record<string, string>, indirect: Record<string, string>}} testDependencies
 * @param {{direct: Record<string, string>, indirect: Record<string, string>}} regularDependencies
 * @returns {{direct: Record<string, string>, indirect: Record<string, string>}}
 */
function filterOutDuplicateDependencies(testDependencies, regularDependencies) {
  return {
    direct: filterOutDuplicateDependenciesForSection(
      testDependencies.direct,
      regularDependencies.direct
    ),
    indirect: filterOutDuplicateDependenciesForSection(
      testDependencies.indirect,
      {...regularDependencies.direct, ...regularDependencies.indirect}
    )
  };
}

/**
 * Filter out test-dependencies that are already in the regular dependencies (only on a section of the dependencies).
 *
 * @param {Record<string, string>} testDependencies
 * @param {Record<string, string>} regularDependencies
 * @returns {Record<string, string>}
 */
function filterOutDuplicateDependenciesForSection(
  testDependencies,
  regularDependencies
) {
  return Object.fromEntries(
    Object.entries(testDependencies).filter(
      ([pkg, _]) => !regularDependencies[pkg]
    )
  );
}

/**
 * Update versions of dependencies to their latest (compatible) version.
 *
 * @param {Options} options
 * @param {ApplicationElmJson} elmJson
 * @returns {ApplicationElmJson}
 */
function update(options, elmJson) {
  const extra = {
    'stil4m/elm-syntax': '7.0.0 <= v < 8.0.0',
    'jfmengels/elm-review': MinVersion.supportedRange
  };

  for (const [pkg, version] of Object.entries(elmJson.dependencies.direct)) {
    extra[pkg] = `${version} <= v < ${nextMajorVersion(version)}`;
  }

  delete elmJson.dependencies.direct['jfmengels/elm-review'];
  delete elmJson.dependencies.direct['stil4m/elm-syntax'];

  const stringifiedElmJson = JSON.stringify({
    ...elmJson,
    dependencies: {direct: {}, indirect: {}},
    'test-dependencies': {direct: {}, indirect: {}}
  });

  elmJson.dependencies = solve(
    options,
    elmJson['elm-version'],
    stringifiedElmJson,
    extra,
    true
  );

  const testDependenciesEntries = Object.entries(
    elmJson['test-dependencies'].direct
  );
  if (testDependenciesEntries.length > 0) {
    /** @type {Record<string, string>} */
    const packagesToAdd = {};
    for (const [pkg, version] of testDependenciesEntries) {
      packagesToAdd[pkg] = `${version} <= v < ${nextMajorVersion(version)}`;
    }

    const testDependencies = solve(
      options,
      elmJson['elm-version'],
      stringifiedElmJson,
      packagesToAdd,
      true
    );

    elmJson['test-dependencies'] = filterOutDuplicateDependencies(
      testDependencies,
      elmJson.dependencies
    );
  }

  teardownDependenciesProvider();

  return elmJson;
}

function teardownDependenciesProvider() {
  if (dependencyProvider) {
    dependencyProvider.tearDown();
    dependencyProvider = null;
  }
}

/**
 * @import {Options} from './types/options';
 * @import {VersionString, VersionRange} from './types/version';
 * @import {ApplicationElmJson, ApplicationDependencies, ApplicationDependencyList, PackageName, PackageDependencyList} from './types/content';
 */
const path = require('node:path');
const chalk = require('chalk');
const {DependencyProvider} = require('./dependency-provider');
const ErrorMessage = require('./error-message');
const FS = require('./fs-wrapper');
const MinVersion = require('./min-version');
const {intoError} = require('./utils');

/** @type {DependencyProvider | null} */
let dependencyProvider = null;

const parseElmFolder = path.join(__dirname, '../parseElm');

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
    'elm/parser': '1.0.0 <= v < 2.0.0',
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
  } catch (err) {
    const error = intoError(err);
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
 * @param {VersionString} elmVersion
 * @param {VersionString} elmSyntaxVersion
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
  /** @type Record<PackageName, VersionRange> **/
  const extra = {
    'stil4m/elm-syntax': `${elmSyntaxVersion} <= v < ${nextVersion(
      elmSyntaxVersion,
      'patch'
    )}`
  };
  for (const [
    /** @type PackageName **/ name,
    /** @type VersionString **/ version
  ] of Object.entries(elmJson.dependencies.direct)) {
    // @ts-expect-error(TS7053): Can't figure out how to type check this.
    extra[name] = `${version} <= v < ${nextVersion(version, 'major')}`;
  }

  elmJson.dependencies.direct = {};

  elmJson.dependencies = solve(
    options,
    elmVersion,
    JSON.stringify(elmJson),
    extra,
    false
  );
  return elmJson;
}

/**
 * @param {Options} options
 * @param {VersionString} elmVersion
 * @param {string} elmJson
 * @param {Record<string, string>} extra
 * @param {boolean} onlineFirst
 * @returns {ApplicationDependencies}
 */
function solve(options, elmVersion, elmJson, extra, onlineFirst) {
  if (dependencyProvider === null) {
    dependencyProvider = new DependencyProvider();
  }

  try {
    const dependencies = /** @type {unknown} */ (
      JSON.parse(
        onlineFirst && !options.offline
          ? dependencyProvider.solveOnline(options, elmVersion, elmJson, extra)
          : dependencyProvider.solveOffline(options, elmVersion, elmJson, extra)
      )
    );

    return /** @type {ApplicationDependencies} */ (dependencies);
  } catch (error) {
    if (options.offline) {
      throw error;
    }

    const dependencies = /** @type {unknown} */ (
      JSON.parse(
        onlineFirst
          ? dependencyProvider.solveOffline(options, elmVersion, elmJson, extra)
          : dependencyProvider.solveOnline(options, elmVersion, elmJson, extra)
      )
    );

    return /** @type {ApplicationDependencies} */ (dependencies);
  }
}

/**
 * @param {VersionString} version
 * @param {'major' | 'minor' | 'patch'} bump
 * @returns {VersionString} the next version.
 *   Ex: 2.13.0 -> 3.0.0 (major)
 *   Ex: 2.13.0 -> 2.13.1 (patch)
 */
function nextVersion(version, bump) {
  const [major, minor, patch] = version.split('.');

  const majorNum = Number.parseInt(major, 10);
  if (bump === 'major') {
    return `${majorNum + 1}.0.0`;
  }

  const minorNum = Number.parseInt(minor, 10);
  if (bump === 'minor') {
    return `${majorNum}.${minorNum + 1}.0`;
  }

  const patchNum = Number.parseInt(patch, 10);
  if (bump === 'patch') {
    return `${majorNum}.${minorNum}.${patchNum + 1}`;
  }

  throw new TypeError("TS doesn't infer this, strangely.");
}

/**
 * Create a new elm.json with basic `elm-review` dependencies.
 *
 * @param {Options} options
 * @param {VersionString} elmVersion
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
 * @param {ApplicationDependencies} testDependencies
 * @param {ApplicationDependencies} regularDependencies
 * @returns {ApplicationDependencies}
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
 * @param {ApplicationDependencyList} testDependencies
 * @param {ApplicationDependencyList} regularDependencies
 * @returns {ApplicationDependencyList}
 */
function filterOutDuplicateDependenciesForSection(
  testDependencies,
  regularDependencies
) {
  return Object.fromEntries(
    Object.entries(testDependencies).filter(
      ([pkg]) => !regularDependencies[/** @type {PackageName} */ (pkg)]
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
  /** @type {PackageDependencyList} */
  const extra = {
    'stil4m/elm-syntax': '7.0.0 <= v < 8.0.0',
    'jfmengels/elm-review': MinVersion.supportedRange
  };

  for (const [pkg, version] of Object.entries(elmJson.dependencies.direct)) {
    extra[/** @type {PackageName} */ (pkg)] = `${version} <= v < ${nextVersion(
      version,
      'major'
    )}`;
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

  const testDependenciesEntries =
    /** @type {[PackageName, VersionString][]} */
    (Object.entries(elmJson['test-dependencies'].direct));
  if (testDependenciesEntries.length > 0) {
    /** @type {PackageDependencyList} */
    const packagesToAdd = {};
    for (const [pkg, version] of testDependenciesEntries) {
      packagesToAdd[pkg] = `${version} <= v < ${nextVersion(version, 'major')}`;
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

/**
 * @returns {void}
 */
function teardownDependenciesProvider() {
  if (dependencyProvider) {
    dependencyProvider.tearDown();
    dependencyProvider = null;
  }
}

module.exports = {
  addRequiredDependencies,
  createNewReviewElmJson,
  update,
  addElmSyntax
};

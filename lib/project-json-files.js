/**
 * @import {Path} from './types/path';
 * @import {VersionString} from './types/version';
 * @import {Options} from './types/options';
 * @import {PackageElmJson, PackageName} from './types/content';
 */
const os = require('node:os');
const path = require('pathe');
const got = require('got').default;
const FS = require('./fs-wrapper');

const elmRoot =
  process.env.ELM_HOME ??
  path.join(
    os.homedir(),
    os.platform() === 'win32' ? 'AppData/Roaming/elm' : '.elm'
  );

/**
 * Get the `elm.json` file for a dependency.
 *
 * @param {Options} options
 * @param {VersionString} elmVersion
 * @param {PackageName} name
 * @param {VersionString} packageVersion
 * @returns {Promise<PackageElmJson>}
 */
async function getElmJson(options, elmVersion, name, packageVersion) {
  try {
    // Look for the dependency in ELM_HOME first
    return await getElmJsonFromElmHome(elmVersion, name, packageVersion);
  } catch {
    // Then in the dependency cache for elm-review
    const cacheLocation = elmReviewDependencyCache(
      options,
      elmVersion,
      name,
      packageVersion,
      'elm.json'
    );
    try {
      return /** @type {PackageElmJson} */ (
        await FS.readJsonFile(cacheLocation)
      );
    } catch (error) {
      // Finally, try to download it from the packages website
      if (options.offline) {
        // Unless we're in offline mode
        throw error;
      }

      return await readFromPackagesWebsite(
        cacheLocation,
        name,
        packageVersion,
        'elm.json'
      );
    }
  }
}

// TODO(@jfmengels): Empty this cache at some point?
//   Note that we might need it in watch and fix mode, but not otherwise.
/** @type {Map<string, Promise<PackageElmJson>>} */
const elmJsonInElmHomePromises = new Map();

/**
 * @param {VersionString} elmVersion
 * @param {string} name
 * @param {string} packageVersion
 * @returns {Promise<PackageElmJson>}
 */
async function getElmJsonFromElmHome(elmVersion, name, packageVersion) {
  const key = `${elmVersion}-${name}-${packageVersion}`;
  let promise = elmJsonInElmHomePromises.get(key);
  if (promise) {
    return await promise;
  }

  const elmJsonPath = getElmJsonFromElmHomePath(
    elmVersion,
    name,
    packageVersion
  );
  promise = /** @type {Promise<PackageElmJson>} */ (
    FS.readJsonFile(elmJsonPath)
  );
  elmJsonInElmHomePromises.set(key, promise);
  return await promise;
}

/**
 * @param {VersionString} elmVersion
 * @param {string} name
 * @param {string} packageVersion
 * @returns {Path}
 */
function getElmJsonFromElmHomePath(elmVersion, name, packageVersion) {
  return path.join(
    getPackagePathInElmHome(elmVersion, name),
    packageVersion,
    'elm.json'
  );
}

/**
 * @param {VersionString} elmVersion
 * @param {string} name
 * @returns {Path}
 */
function getPackagePathInElmHome(elmVersion, name) {
  return path.join(elmRoot, elmVersion, 'packages', name);
}

/**
 * Get the docs.json file for a dependency.
 *
 * @param {Options} options
 * @param {VersionString} elmVersion
 * @param {PackageName} name
 * @param {VersionString} packageVersion
 * @returns {Promise<unknown>}
 */
async function getDocsJson(options, elmVersion, name, packageVersion) {
  try {
    return await FS.readJsonFile(
      path.join(
        elmRoot,
        elmVersion,
        'packages',
        name,
        packageVersion,
        'docs.json'
      )
    );
  } catch {
    const cacheLocation = elmReviewDependencyCache(
      options,
      elmVersion,
      name,
      packageVersion,
      'docs.json'
    );
    try {
      return await FS.readJsonFile(cacheLocation);
    } catch (error) {
      // Finally, try to download it from the packages website
      if (options.offline) {
        // Unless we're in offline mode
        throw error;
      }

      return await readFromPackagesWebsite(
        cacheLocation,
        name,
        packageVersion,
        'docs.json'
      );
    }
  }
}

/**
 * Download a file from the Elm package registry.
 *
 * @param {string} cacheLocation
 * @param {string} packageName
 * @param {string} packageVersion
 * @param {'elm.json' | 'docs.json'} file
 * @returns {Promise<PackageElmJson>}
 */
async function readFromPackagesWebsite(
  cacheLocation,
  packageName,
  packageVersion,
  file
) {
  // TODO(@lishaduck) [engine:node@>=21]: We can use `fetch` now.
  const response = await got(
    `https://package.elm-lang.org/packages/${packageName}/${packageVersion}/${file}`
  );

  const json = /** @type {PackageElmJson} */ (
    /** @type {unknown} */ (JSON.parse(response.body))
  );
  cachePackage(cacheLocation, json).catch(() => {});
  return json;
}

/**
 * @param {Path} cacheLocation
 * @param {PackageElmJson} json
 * @returns {Promise<void>}
 */
async function cachePackage(cacheLocation, json) {
  await FS.mkdirp(path.dirname(cacheLocation));
  await FS.writeJson(cacheLocation, json, 0);
}

/**
 * Get the path to where a project file would be cached.
 *
 * @param {Options} options
 * @param {VersionString} elmVersion
 * @param {string} name
 * @param {string} packageVersion
 * @param {string} file
 * @returns {string}
 */
function elmReviewDependencyCache(
  options,
  elmVersion,
  name,
  packageVersion,
  file
) {
  return path.join(
    elmHomeCache(options.packageJsonVersion),
    elmVersion,
    'packages',
    name,
    packageVersion,
    file
  );
}

/**
 * @param {string} packageJsonVersion
 * @returns {Path}
 */
function elmHomeCache(packageJsonVersion) {
  return path.join(elmRoot, 'elm-review', packageJsonVersion);
}

module.exports = {
  getElmJson,
  getPackagePathInElmHome,
  getElmJsonFromElmHomePath,
  getElmJsonFromElmHome,
  elmReviewDependencyCache,
  getDocsJson,
  elmHomeCache
};

const path = require('path');
const os = require('os');
const {default: got} = require('got');
const FS = require('./fs-wrapper');

/**
 * @typedef { import("./types/path").Path } Path
 * @typedef { import("./types/elm-version").ElmVersion } ElmVersion
 * @typedef { import("./types/options").Options } Options
 * @typedef { import("./types/content").ElmJson } ElmJson
 */

const elmRoot =
  process.env.ELM_HOME ||
  path.join(
    os.homedir(),
    os.platform() === 'win32' ? 'AppData/Roaming/elm' : '.elm'
  );

/** Get the elm.json file for a dependency.
 *
 * @param {Options} options
 * @param {string} elmVersion
 * @param {string} name
 * @param {string} packageVersion
 * @returns {Promise<Object>}
 */
function getElmJson(options, elmVersion, name, packageVersion) {
  // Look for the dependency in ELM_HOME first
  return (
    getElmJsonFromElmHome(elmVersion, name, packageVersion)
      // Then in the dependency cache for elm-review
      .catch(() => {
        const cacheLocation = elmReviewDependencyCache(
          options,
          elmVersion,
          name,
          packageVersion,
          'elm.json'
        );
        return FS.readJsonFile(cacheLocation).catch((error) => {
          // Finally, try to download it from the packages website
          if (options.offline) {
            // Unless we're in offline mode
            throw error;
          }

          return readFromPackagesWebsite(
            cacheLocation,
            name,
            packageVersion,
            'elm.json'
          );
        });
      })
  );
}

// TODO Empty this cache at some point?
// Note that we might need it in watch and fix mode, but not otherwise.
const elmJsonInElmHomePromises = new Map();

/**
 * @param {ElmVersion} elmVersion
 * @param {string} name
 * @param {string} packageVersion
 * @return {Promise<ElmJson>}
 */
function getElmJsonFromElmHome(elmVersion, name, packageVersion) {
  const key = `${elmVersion}-${name}-${packageVersion}`;
  let promise = elmJsonInElmHomePromises.get(key);
  if (promise) {
    return promise;
  }

  const elmJsonPath = getElmJsonFromElmHomePath(
    elmVersion,
    name,
    packageVersion
  );
  promise = FS.readJsonFile(elmJsonPath);
  elmJsonInElmHomePromises.set(key, promise);
  return promise;
}

/**
 * @param {ElmVersion} elmVersion
 * @param {string} name
 * @param {string} packageVersion
 * @return {Path}
 */
function getElmJsonFromElmHomePath(elmVersion, name, packageVersion) {
  return path.join(
    getPackagePathInElmHome(elmVersion, name),
    packageVersion,
    'elm.json'
  );
}

/**
 * @param {ElmVersion} elmVersion
 * @param {string} name
 * @return {Path}
 */
function getPackagePathInElmHome(elmVersion, name) {
  return path.join(elmRoot, elmVersion, 'packages', name);
}

/** Get the docs.json file for a dependency.
 *
 * @param {Options} options
 * @param {string} elmVersion
 * @param {string} name
 * @param {string} packageVersion
 * @returns {Promise<Object>}
 */
function getDocsJson(options, elmVersion, name, packageVersion) {
  return FS.readJsonFile(
    path.join(
      elmRoot,
      elmVersion,
      'packages',
      name,
      packageVersion,
      'docs.json'
    )
  ).catch(() => {
    const cacheLocation = elmReviewDependencyCache(
      options,
      elmVersion,
      name,
      packageVersion,
      'docs.json'
    );
    return FS.readJsonFile(cacheLocation).catch((error) => {
      // Finally, try to download it from the packages website
      if (options.offline) {
        // Unless we're in offline mode
        throw error;
      }

      return readFromPackagesWebsite(
        cacheLocation,
        name,
        packageVersion,
        'docs.json'
      );
    });
  });
}

/** Download a file from the Elm package registry.
 *
 * @param {string} cacheLocation
 * @param {string} packageName
 * @param {string} packageVersion
 * @param {'elm.json' | 'docs.json'} file
 * @returns {Promise<object>}
 */
async function readFromPackagesWebsite(
  cacheLocation,
  packageName,
  packageVersion,
  file
) {
  const response = await got(
    `https://package.elm-lang.org/packages/${packageName}/${packageVersion}/${file}`
  );
  const json = JSON.parse(response.body);
  cacheFile(cacheLocation, json).catch(() => {});
  return json;
}

/**
 *
 * @param {Path} cacheLocation
 * @param {Object} json
 * @return {Promise<void>}
 */
async function cacheFile(cacheLocation, json) {
  await FS.mkdirp(path.dirname(cacheLocation));
  return FS.writeJson(cacheLocation, json, 0);
}

/** Get the path to where a project file would be cached.
 *
 * @param {Options} options
 * @param {string} elmVersion
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
 * @return {Path}
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

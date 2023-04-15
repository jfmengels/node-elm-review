const path = require('path');
const util = require('util');
const os = require('os');
const got = require('got');
const fs = require('fs-extra');

const fsMkdirp = util.promisify(fs.mkdirp);
const fsReadJson = util.promisify(fs.readJson);
const fsWriteJson = util.promisify(fs.writeJson);

const elmRoot =
  process.env.ELM_HOME ||
  path.join(
    os.homedir(),
    os.platform() === 'win32' ? 'AppData/Roaming/elm' : '.elm'
  );

function getElmJson(
  elmVersion,
  elmReviewDependencyCache,
  name,
  packageVersion
) {
  // Look for the dependency in ELM_HOME first
  return (
    getElmJsonFromElmHome(elmVersion, name, packageVersion)
      // Then in the dependency cache for elm-review
      .catch(() => fsReadJson(path.join(elmReviewDependencyCache, 'elm.json')))
      .catch(() =>
        // Finally, try to download it from the packages website
        readFromPackagesWebsite(name, packageVersion, 'elm.json').then((result) => {
          // And cache it for future uses
          cacheFile(
            elmReviewDependencyCache,
            'elm.json',
            result
          ).catch(() => {});
          return result;
        })
      )
  );
}

// TODO Empty this cache at some point?
// Note that we might need it in watch and fix mode, but not otherwise.
const elmJsonInElmHomePromises = new Map();
function getElmJsonFromElmHome(elmVersion, name, packageVersion) {
  const key = `${elmVersion}-${name}-${packageVersion}`;
  let promise = elmJsonInElmHomePromises.get(key);
  if (promise) {
    return promise;
  }

  const directory = path.join(
    elmRoot,
    elmVersion,
    'packages',
    name,
    packageVersion
  );
  promise = fsReadJson(path.join(directory, 'elm.json'));
  elmJsonInElmHomePromises.set(key, promise);
  return promise;
}

function getDocsJson(
  directory,
  elmReviewDependencyCache,
  name,
  packageVersion
) {
  return fsReadJson(path.join(directory, 'docs.json'))
    .catch(() => fsReadJson(path.join(elmReviewDependencyCache, 'docs.json')))
    .catch(() =>
      readFromPackagesWebsite(name, packageVersion, 'docs.json').then((result) => {
        cacheFile(
          elmReviewDependencyCache,
          'docs.json',
          result
        ).catch(() => {});
        return result;
      })
    );
}

/** Download a file from the Elm package registry.
 *
 * @param {string} packageName
 * @param {string} packageVersion
 * @param {'elm.json' | 'docs.json'} file
 * @returns {Promise<object>}
 */
async function readFromPackagesWebsite(packageName, packageVersion, file) {
  const response = await got(
    `https://package.elm-lang.org/packages/${packageName}/${packageVersion}/${file}`
  );
  return JSON.parse(response.body);
}

async function cacheFile(directory, name, jsonContent) {
  await fsMkdirp(directory).catch(() => {});
  return fsWriteJson(path.join(directory, name), jsonContent);
}

module.exports = {
  getElmJson,
  getElmJsonFromElmHome,
  getDocsJson
};

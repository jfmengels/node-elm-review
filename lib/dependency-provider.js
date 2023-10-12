const fs = require('fs');
const path = require('path');
const wasm = require('elm-solve-deps-wasm');
const ProjectJsonFiles = require('./project-json-files');
const SyncGet = require('./sync-get');
const collator = new Intl.Collator('en', {numeric: true}); // for sorting SemVer strings

// Initialization work done only once.
wasm.init();
const syncGetWorker /*: {| get: (string) => string, shutDown: () => void |} */ =
  SyncGet.startWorker();

// Cache of existing versions according to the package website.
class OnlineVersionsCache {
  map /*: Map<string, Array<string>> */ = new Map();

  update(elmVersion /*: string */) {
    const pubgrubHome = path.join(
      ProjectJsonFiles.elmRoot,
      'elm-review',
      'dependencies-cache',
      elmVersion
    );
    fs.mkdirSync(pubgrubHome, {recursive: true});
    const cachePath = path.join(pubgrubHome, 'versions_cache.json');
    const remotePackagesUrl = 'https://package.elm-lang.org/all-packages';
    if (this.map.size === 0) {
      let cacheFile;
      try {
        // Read from disk existing versions which are already cached.
        cacheFile = fs.readFileSync(cachePath, 'utf8');
      } catch (_) {
        // The cache file does not exist so let's reset it.
        this.map = onlineVersionsFromScratch(cachePath, remotePackagesUrl);
        return;
      }
      try {
        this.map = parseOnlineVersions(JSON.parse(cacheFile));
      } catch (error) {
        throw new Error(
          `Failed to parse the cache file ${cachePath}.\n${error.message}`
        );
      }
    }
    this.updateWithRequestSince(cachePath, remotePackagesUrl);
  }

  // Update the cache with a request to the package server.
  updateWithRequestSince(
    cachePath /*: string */,
    remotePackagesUrl /*: string */
  ) /*: void */ {
    // Count existing versions.
    let versionsCount = 0;
    for (const versions of this.map.values()) {
      versionsCount += versions.length;
    }

    // Complete cache with a remote call to the package server.
    const remoteUrl = remotePackagesUrl + '/since/' + (versionsCount - 1); // -1 to check if no package was deleted.
    const newVersions = JSON.parse(syncGetWorker.get(remoteUrl));
    if (newVersions.length === 0) {
      // Reload from scratch since it means at least one package was deleted from the registry.
      this.map = onlineVersionsFromScratch(cachePath, remotePackagesUrl);
      return;
    }
    // Check that the last package in the list was already in cache
    // since the list returned by the package server is sorted newest first.
    const {pkg, version} = splitPkgVersion(newVersions.pop());
    const cachePkgVersions = this.map.get(pkg);
    if (
      cachePkgVersions !== undefined &&
      cachePkgVersions[cachePkgVersions.length - 1] === version
    ) {
      // Insert (in reverse) newVersions into onlineVersionsCache map.
      for (const pkgVersion of newVersions.reverse()) {
        const {pkg, version} = splitPkgVersion(pkgVersion);
        const versionsOfPkg = this.map.get(pkg);
        if (versionsOfPkg === undefined) {
          this.map.set(pkg, [version]);
        } else {
          versionsOfPkg.push(version);
        }
      }
      // Save the updated onlineVersionsCache to disk.
      const onlineVersions = Object.fromEntries(this.map.entries());
      fs.writeFileSync(cachePath, JSON.stringify(onlineVersions));
    } else {
      // There was a problem and a package got deleted from the server.
      this.map = onlineVersionsFromScratch(cachePath, remotePackagesUrl);
    }
  }

  getVersions(pkg /*: string */) /*: Array<string> */ {
    const versions = this.map.get(pkg);
    return versions === undefined ? [] : versions;
  }
}

class OnlineAvailableVersionLister {
  // Memoization cache to avoid doing the same work twice in list.
  memoCache /*: Map<string, Array<string>> */ = new Map();
  onlineCache /*: OnlineVersionsCache */;

  constructor(
    onlineCache /*: OnlineVersionsCache */,
    elmVersion /*: string */
  ) {
    onlineCache.update(elmVersion);
    this.onlineCache = onlineCache;
  }

  list(elmVersion /*: string */, pkg /*: string */) /*: Array<string> */ {
    const memoVersions = this.memoCache.get(pkg);
    if (memoVersions !== undefined) {
      return memoVersions;
    }
    const offlineVersions = readVersionsInElmHomeAndSort(elmVersion, pkg);
    const allVersionsSet = new Set(this.onlineCache.getVersions(pkg));
    // Combine local and online versions.
    for (const version of offlineVersions) {
      allVersionsSet.add(version);
    }
    const allVersions = [...allVersionsSet].sort(flippedSemverCompare);
    this.memoCache.set(pkg, allVersions);
    return allVersions;
  }
}

class OfflineAvailableVersionLister {
  // Memoization cache to avoid doing the same work twice in list.
  cache /*: Map<string, Array<string>> */ = new Map();

  list(elmVersion, pkg /*: string */) /*: Array<string> */ {
    const memoVersions = this.cache.get(pkg);
    if (memoVersions !== undefined) {
      return memoVersions;
    }

    const offlineVersions = readVersionsInElmHomeAndSort(elmVersion, pkg);

    this.cache.set(pkg, offlineVersions);
    return offlineVersions;
  }
}

function readVersionsInElmHomeAndSort(
  elmVersion /*: string*/,
  pkg /*: string */
) /*: Array<string> */ {
  const pkgPath = ProjectJsonFiles.getPackagePathInElmHome(elmVersion, pkg);
  let offlineVersions;
  try {
    offlineVersions = fs.readdirSync(pkgPath);
  } catch (_) {
    // The directory doesn't exist or we don't have permissions.
    // It's fine to catch all cases and return an empty list.
    offlineVersions = [];
  }

  return offlineVersions.sort(flippedSemverCompare);
}

class DependencyProvider {
  cache /*: OnlineVersionsCache */ = new OnlineVersionsCache();
  elmVersion /*: string */;

  constructor(elmVersion /*: string */) {
    this.elmVersion = elmVersion;
  }

  // Solve dependencies completely offline, without any http request.
  solveOffline(
    elmJson /*: string */,
    extra /*: { [string]: string } */
  ) /*: string */ {
    const lister = new OfflineAvailableVersionLister();
    try {
      return wasm.solve_deps(
        elmJson,
        false,
        extra,
        fetchElmJsonOffline(this.elmVersion),
        (pkg) => lister.list(this.elmVersion, pkg)
      );
    } catch (errorMessage) {
      throw new Error(errorMessage);
    }
  }

  // Solve dependencies with http requests when required.
  solveOnline(
    elmJson /*: string */,
    extra /*: { [string]: string } */
  ) /*: string */ {
    const lister = new OnlineAvailableVersionLister(
      this.cache,
      this.elmVersion
    );
    try {
      return wasm.solve_deps(elmJson, false, extra, fetchElmJsonOnline, (pkg) =>
        lister.list(this.elmVersion, pkg)
      );
    } catch (errorMessage) {
      throw new Error(errorMessage);
    }
  }
}

function fetchElmJsonOnline(
  pkg /*: string */,
  version /*: string */
) /*: string */ {
  try {
    return fetchElmJsonOffline(pkg, version);
  } catch (_) {
    // `fetchElmJsonOffline` can only fail in ways that are either expected
    // (such as file does not exist or no permissions)
    // or because there was an error parsing `pkg` and `version`.
    // In such case, this will throw again with `cacheElmJsonPath()` so it's fine.
    const remoteUrl = remoteElmJsonUrl(pkg, version);
    const elmJson = syncGetWorker.get(remoteUrl);
    const cachePath = cacheElmJsonPath(pkg, version);
    const parentDir = path.dirname(cachePath);
    fs.mkdirSync(parentDir, {recursive: true});
    fs.writeFileSync(cachePath, elmJson);
    return elmJson;
  }
}

function fetchElmJsonOffline(elmVersion) {
  return (pkg /*: string */, version /*: string */) /*: string */ => {
    try {
      return fs.readFileSync(
        ProjectJsonFiles.getElmJsonFromElmHomePath(elmVersion, pkg, version),
        'utf8'
      );
    } catch (_) {
      // The read can only fail if the elm.json file does not exist
      // or if we don't have the permissions to read it so it's fine to catch all.
      // Otherwise, it means that `homeElmJsonPath()` failed while processing `pkg` and `version`.
      // In such case, again, it's fine to catch all since the next call to `cacheElmJsonPath()`
      // will fail the same anyway.
      return fs.readFileSync(cacheElmJsonPath(pkg, version), 'utf8');
    }
  };
}

// Reset the cache of existing versions from scratch
// with a request to the package server.
function onlineVersionsFromScratch(
  cachePath /*: string */,
  remotePackagesUrl /*: string */
) /*: Map<string, Array<string>> */ {
  const onlineVersionsJson = syncGetWorker.get(remotePackagesUrl);
  fs.writeFileSync(cachePath, onlineVersionsJson);
  const onlineVersions = JSON.parse(onlineVersionsJson);
  try {
    return parseOnlineVersions(onlineVersions);
  } catch (error) {
    throw new Error(
      `Failed to parse the response from the request to ${remotePackagesUrl}.\n${error.message}`
    );
  }
}

// Helper functions ##################################################

/* Compares two versions so that newer versions appear first when sorting with this function. */
function flippedSemverCompare(a /*: string */, b /*: string */) /*: number */ {
  return collator.compare(b, a);
}

function parseOnlineVersions(
  json /*: mixed */
) /*: Map<string, Array<string>> */ {
  if (typeof json !== 'object' || json === null || Array.isArray(json)) {
    throw new Error(
      `Expected an object, but got: ${
        json === null ? 'null' : Array.isArray(json) ? 'Array' : typeof json
      }`
    );
  }

  const result = new Map();

  for (const [key, value] of Object.entries(json)) {
    result.set(key, parseVersions(key, value));
  }

  return result;
}

function parseVersions(
  key /*: string */,
  json /*: mixed */
) /*: Array<string> */ {
  if (!Array.isArray(json)) {
    throw new Error(
      `Expected ${JSON.stringify(key)} to be an array, but got: ${typeof json}`
    );
  }

  for (const [index, item] of json.entries()) {
    if (typeof item !== 'string') {
      throw new Error(
        `Expected${JSON.stringify(
          key
        )}->${index} to be a string, but got: ${typeof item}`
      );
    }
  }

  return json;
}

function remoteElmJsonUrl(
  pkg /*: string */,
  version /*: string */
) /*: string */ {
  return `https://package.elm-lang.org/packages/${pkg}/${version}/elm.json`;
}

function cacheElmJsonPath(
  pkg /*: string */,
  version /*: string */
) /*: string */ {
  const [author, pkgName] = pkg.split('/');
  return path.join(
    ProjectJsonFiles.elmRoot,
    'pubgrub',
    'elm_json_cache',
    author,
    pkgName,
    version,
    'elm.json'
  );
}

function splitPkgVersion(str /*: string */) /*: {
  pkg: string,
  version: string,
} */ {
  const parts = str.split('@');
  return {pkg: parts[0], version: parts[1]};
}

module.exports = DependencyProvider;
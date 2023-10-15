const fs = require('fs');
const path = require('path');
const wasm = require('elm-solve-deps-wasm');
const ProjectJsonFiles = require('./project-json-files');
const SyncGet = require('./sync-get');
const collator = new Intl.Collator('en', {numeric: true}); // For sorting SemVer strings

/** @type {boolean} */
let wasmWasInitialized = false;
/** @type {{ get: (string) => string, shutDown: () => void } | null} */
let syncGetWorker = null;

class DependencyProvider {
  /** @type {OnlineVersionsCache} */
  cache;
  /** @type {string} */
  elmVersion;

  /**
   * @param {string} elmVersion
   */
  constructor(elmVersion) {
    this.cache = new OnlineVersionsCache();
    this.elmVersion = elmVersion;
    if (!wasmWasInitialized) {
      wasm.init();
      wasmWasInitialized = true;
    }

    syncGetWorker = SyncGet.startWorker();
  }

  /** Solve dependencies completely offline, without any http request.
   *
   * @param {string} elmJson
   * @param {Record<string, string>} extra
   * @return {string}
   */
  solveOffline(elmJson, extra) {
    const lister = new OfflineAvailableVersionLister();
    try {
      return wasm.solve_deps(
        elmJson,
        false,
        extra,
        fetchElmJsonOffline(this.elmVersion),
        (/** @type {string} */ pkg) => lister.list(this.elmVersion, pkg)
      );
    } catch (errorMessage) {
      throw new Error(errorMessage);
    }
  }

  /** Solve dependencies with http requests when required.
   *
   * @param {string} elmJson
   * @param {Record<string, string>} extra
   * @return {string}
   */
  solveOnline(elmJson, extra) {
    const lister = new OnlineAvailableVersionLister(
      this.cache,
      this.elmVersion
    );
    try {
      return wasm.solve_deps(
        elmJson,
        false,
        extra,
        fetchElmJsonOnline(this.elmVersion),
        (pkg) => lister.list(this.elmVersion, pkg)
      );
    } catch (errorMessage) {
      throw new Error(errorMessage);
    }
  }

  /**
   * @returns {void}
   */
  tearDown() {
    if (!syncGetWorker) {
      return;
    }

    syncGetWorker.shutDown();
    syncGetWorker = null;
  }
}

class OfflineAvailableVersionLister {
  /** Memoization cache to avoid doing the same work twice in list.
   * @type {Map<string, string[]>}
   */
  cache = new Map();

  /**
   * @param {string} elmVersion
   * @param {string} pkg
   * @return {string[]}
   */
  list(elmVersion, pkg) {
    const memoVersions = this.cache.get(pkg);
    if (memoVersions !== undefined) {
      return memoVersions;
    }

    const offlineVersions = readVersionsInElmHomeAndSort(elmVersion, pkg);

    this.cache.set(pkg, offlineVersions);
    return offlineVersions;
  }
}

/** Cache of existing versions according to the package website. */
class OnlineVersionsCache {
  /** @type {Map<string, Array<string>>} */
  map = new Map();

  /**
   * @param {string} elmVersion
   * @returns {void}
   */
  update(elmVersion) {
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

  /** Update the cache with a request to the package server.
   *
   * @param {string} cachePath
   * @param {string} remotePackagesUrl
   * @returns {void}
   */
  updateWithRequestSince(cachePath, remotePackagesUrl) {
    // Count existing versions.
    let versionsCount = 0;
    for (const versions of this.map.values()) {
      versionsCount += versions.length;
    }

    // Complete cache with a remote call to the package server.
    const remoteUrl = remotePackagesUrl + '/since/' + (versionsCount - 1); // -1 to check if no package was deleted.
    if (!syncGetWorker) {
      return;
    }

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

  /** List the versions for a package.
   *
   * @param {string} pkg
   * @returns {string[]}
   */
  getVersions(pkg) {
    const versions = this.map.get(pkg);
    return versions === undefined ? [] : versions;
  }
}

class OnlineAvailableVersionLister {
  /** Memoization cache to avoid doing the same work twice in list.
   * @type {Map<string, Array<string>>}
   */
  memoCache = new Map();
  /** @type {OnlineVersionsCache} */
  onlineCache;

  /**
   * @param {OnlineVersionsCache} onlineCache
   * @param {string} elmVersion
   */
  constructor(onlineCache, elmVersion) {
    onlineCache.update(elmVersion);
    this.onlineCache = onlineCache;
  }

  /**
   * @param {string} elmVersion
   * @param {string} pkg
   * @return {string[]}
   */
  list(elmVersion, pkg) {
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

/**
 * @param {string} elmVersion
 * @param {string} pkg
 * @return {string[]}
 */
function readVersionsInElmHomeAndSort(elmVersion, pkg) {
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

/** Solve dependencies completely offline, without any http request.
 *
 * @param {string} elmVersion
 * @returns {(pkg: string, version: string) => string}
 */
function fetchElmJsonOnline(elmVersion) {
  return (pkg, version) => {
    try {
      return fetchElmJsonOffline(elmVersion)(pkg, version);
    } catch (_) {
      // `fetchElmJsonOffline` can only fail in ways that are either expected
      // (such as file does not exist or no permissions)
      // or because there was an error parsing `pkg` and `version`.
      // In such case, this will throw again with `cacheElmJsonPath()` so it's fine.
      const remoteUrl = remoteElmJsonUrl(pkg, version);
      if (!syncGetWorker) {
        return '';
      }

      const elmJson = syncGetWorker.get(remoteUrl);
      const cachePath = cacheElmJsonPath(pkg, version);
      const parentDir = path.dirname(cachePath);
      fs.mkdirSync(parentDir, {recursive: true});
      fs.writeFileSync(cachePath, elmJson);
      return elmJson;
    }
  };
}

/**
 * @param {string} elmVersion
 * @returns {(pkg: string, version: string) => string}
 */
function fetchElmJsonOffline(elmVersion) {
  return (pkg, version) => {
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

/** Reset the cache of existing versions from scratch with a request to the package server.
 *
 * @param {string} cachePath
 * @param {string} remotePackagesUrl
 * @return {Map<string, string[]>}
 */
function onlineVersionsFromScratch(cachePath, remotePackagesUrl) {
  if (!syncGetWorker) {
    return new Map();
  }

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

/** Compares two versions so that newer versions appear first when sorting with this function.
 *
 * @param {string} a
 * @param {string} b
 * @return {number}
 */
function flippedSemverCompare(a, b) {
  return collator.compare(b, a);
}

/**
 * @param {unknown} json
 * @return {Map<string, string[]>}
 */
function parseOnlineVersions(json) {
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

/**
 * @param {string} key
 * @param {unknown} json
 * @return {string[]}
 */
function parseVersions(key, json) {
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

/**
 * @param {string} pkg
 * @param {string} version
 * @return {string}
 */
function remoteElmJsonUrl(pkg, version) {
  return `https://package.elm-lang.org/packages/${pkg}/${version}/elm.json`;
}

/**
 * @param {string} pkg
 * @param {string} version
 * @return {string}
 */
function cacheElmJsonPath(pkg, version) {
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

/**
 * @param {string} str
 * @return {{pkg: string, version: string}}
 */
function splitPkgVersion(str) {
  const [pkg, version] = str.split('@');
  return {pkg, version};
}

module.exports = DependencyProvider;

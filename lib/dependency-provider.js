/**
 * @import {Options} from './types/options';
 * @import {Path} from './types/path';
 * @import {VersionString} from './types/version';
 */
const path = require('pathe');
const wasm = require('elm-solve-deps-wasm');
const fs = require('graceful-fs');
const FS = require('./fs-wrapper');
const ProjectJsonFiles = require('./project-json-files');
const SyncGet = require('./sync-get');
const {intoError} = require('./utils');

/** @type {boolean} */
let wasmWasInitialized = false;
/** @type {{ get: (remoteUrl: string) => string, shutDown: () => void } | null} */
let syncGetWorker = null;

class DependencyProvider {
  /** @type {OnlineVersionsCache} */
  cache;

  constructor() {
    this.cache = new OnlineVersionsCache();
    if (!wasmWasInitialized) {
      wasm.init();
      wasmWasInitialized = true;
    }

    syncGetWorker = SyncGet.startWorker();
  }

  /**
   * Solve dependencies completely offline, without any http request.
   *
   * @param {Options} options
   * @param {VersionString} elmVersion
   * @param {string} elmJson
   * @param {Record<string, string>} extra
   * @returns {string}
   */
  solveOffline(options, elmVersion, elmJson, extra) {
    const lister = new OfflineAvailableVersionLister();
    try {
      const indirectDeps = JSON.parse(elmJson).dependencies?.indirect;
      return wasm.solve_deps(
        elmJson,
        false,
        extra,
        (pkg, version) =>
          fetchElmJsonOffline(options, elmVersion, pkg, version),
        (pkg) => lister.list(elmVersion, pkg, indirectDeps?.[pkg])
      );
    } catch (error) {
      throw intoError(error);
    }
  }

  /**
   * Solve dependencies with http requests when required.
   *
   * @param {Options} options
   * @param {VersionString} elmVersion
   * @param {string} elmJson
   * @param {Record<string, string>} extra
   * @returns {string}
   */
  solveOnline(options, elmVersion, elmJson, extra) {
    const lister = new OnlineAvailableVersionLister(
      options,
      this.cache,
      elmVersion
    );
    try {
      const indirectDeps = JSON.parse(elmJson).dependencies?.indirect;
      return wasm.solve_deps(
        elmJson,
        false,
        extra,
        (pkg, version) => fetchElmJsonOnline(options, elmVersion, pkg, version),
        (pkg) => lister.list(elmVersion, pkg, indirectDeps?.[pkg])
      );
    } catch (error) {
      throw intoError(error);
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
  /**
   * Memoization cache to avoid doing the same work twice in list.
   *
   * @type {Map<string, string[]>}
   */
  cache = new Map();

  /**
   * @param {VersionString} elmVersion
   * @param {string} pkg
   * @param {void | string} pinnedVersion
   * @returns {string[]}
   */
  list(elmVersion, pkg, pinnedVersion) {
    const memoVersions = this.cache.get(pkg);
    if (memoVersions !== undefined) {
      return prioritizePinnedIndirectVersion(memoVersions, pinnedVersion);
    }

    const offlineVersions = readVersionsInElmHomeAndSort(elmVersion, pkg);

    this.cache.set(pkg, offlineVersions);
    return prioritizePinnedIndirectVersion(offlineVersions, pinnedVersion);
  }
}

/**
 * Cache of existing versions according to the package website.
 */
class OnlineVersionsCache {
  /** @type {Map<string, string[]>} */
  map = new Map();

  /**
   * @param {Options} options
   * @param {VersionString} elmVersion
   * @returns {void}
   */
  update(options, elmVersion) {
    const cachePath = dependenciesCachePath(
      options.packageJsonVersion,
      elmVersion
    );

    const remotePackagesUrl = 'https://package.elm-lang.org/all-packages';
    if (this.map.size === 0) {
      let cacheFile;
      try {
        // Read from disk existing versions which are already cached.
        cacheFile = fs.readFileSync(cachePath, 'utf8');
      } catch {
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

  /**
   * Update the cache with a request to the package server.
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

    /** @type {string[]} */
    const newVersions = JSON.parse(syncGetWorker.get(remoteUrl));
    if (newVersions.length === 0) {
      // Reload from scratch since it means at least one package was deleted from the registry.
      this.map = onlineVersionsFromScratch(cachePath, remotePackagesUrl);
      return;
    }

    // Check that the last package in the list was already in cache
    // since the list returned by the package server is sorted newest first.
    const {pkg, version} = splitPkgVersion(
      /** @type {string} */ (newVersions.pop())
    );
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

  /**
   * List the versions for a package.
   *
   * @param {string} pkg
   * @returns {string[]}
   */
  getVersions(pkg) {
    const versions = this.map.get(pkg);
    return versions ?? [];
  }
}

class OnlineAvailableVersionLister {
  /**
   * Memoization cache to avoid doing the same work twice in list.
   *
   * @type {Map<string, string[]>}
   */
  memoCache = new Map();
  /** @type {OnlineVersionsCache} */
  onlineCache;

  /**
   * @param {Options} options
   * @param {OnlineVersionsCache} onlineCache
   * @param {VersionString} elmVersion
   */
  constructor(options, onlineCache, elmVersion) {
    onlineCache.update(options, elmVersion);
    this.onlineCache = onlineCache;
  }

  /**
   * @param {VersionString} elmVersion
   * @param {string} pkg
   * @param {void | string} pinnedVersion
   * @returns {string[]}
   */
  list(elmVersion, pkg, pinnedVersion) {
    const memoVersions = this.memoCache.get(pkg);
    if (memoVersions !== undefined) {
      return prioritizePinnedIndirectVersion(memoVersions, pinnedVersion);
    }

    const offlineVersions = readVersionsInElmHomeAndSort(elmVersion, pkg);
    const allVersionsSet = new Set(this.onlineCache.getVersions(pkg));
    // Combine local and online versions.
    for (const version of offlineVersions) {
      allVersionsSet.add(version);
    }

    const allVersions = [...allVersionsSet].sort(flippedSemverCompare);
    this.memoCache.set(pkg, allVersions);
    return prioritizePinnedIndirectVersion(allVersions, pinnedVersion);
  }
}

/**
 * @param {VersionString} elmVersion
 * @param {string} pkg
 * @returns {string[]}
 */
function readVersionsInElmHomeAndSort(elmVersion, pkg) {
  const pkgPath = ProjectJsonFiles.getPackagePathInElmHome(elmVersion, pkg);
  /** @type {string[]} */
  let offlineVersions;
  try {
    offlineVersions = fs.readdirSync(pkgPath);
  } catch {
    // The directory doesn't exist or we don't have permissions.
    // It's fine to catch all cases and return an empty list.
    offlineVersions = [];
  }

  return offlineVersions.sort(flippedSemverCompare);
}

/**
 * Solve dependencies completely offline, without any http request.
 *
 * @param {Options} options
 * @param {VersionString} elmVersion
 * @param {string} pkg
 * @param {string} version
 * @returns {string}
 */
function fetchElmJsonOnline(options, elmVersion, pkg, version) {
  try {
    return fetchElmJsonOffline(options, elmVersion, pkg, version);
  } catch {
    // `fetchElmJsonOffline` can only fail in ways that are either expected
    // (such as file does not exist or no permissions)
    // or because there was an error parsing `pkg` and `version`.
    // In such case, this will throw again with `cacheElmJsonPath()` so it's fine.
    const remoteUrl = remoteElmJsonUrl(pkg, version);
    if (!syncGetWorker) {
      return '';
    }

    const elmJson = syncGetWorker.get(remoteUrl);
    const cachePath = ProjectJsonFiles.elmReviewDependencyCache(
      options,
      elmVersion,
      pkg,
      version,
      'elm.json'
    );
    const parentDir = path.dirname(cachePath);
    fs.mkdirSync(parentDir, {recursive: true});
    fs.writeFileSync(cachePath, elmJson);
    return elmJson;
  }
}

/**
 * @param {Options} options
 * @param {VersionString} elmVersion
 * @param {string} pkg
 * @param {string} version
 * @returns {string}
 */
function fetchElmJsonOffline(options, elmVersion, pkg, version) {
  try {
    return fs.readFileSync(
      ProjectJsonFiles.getElmJsonFromElmHomePath(elmVersion, pkg, version),
      'utf8'
    );
  } catch {
    // The read can only fail if the elm.json file does not exist
    // or if we don't have the permissions to read it so it's fine to catch all.
    // Otherwise, it means that `homeElmJsonPath()` failed while processing `pkg` and `version`.
    // In such case, again, it's fine to catch all since the next call to `cacheElmJsonPath()`
    // will fail the same anyway.
    const cachePath = ProjectJsonFiles.elmReviewDependencyCache(
      options,
      elmVersion,
      pkg,
      version,
      'elm.json'
    );
    return fs.readFileSync(cachePath, 'utf8');
  }
}

/**
 * Reset the cache of existing versions from scratch with a request to the package server.
 *
 * @param {string} cachePath
 * @param {string} remotePackagesUrl
 * @returns {Map<string, string[]>}
 */
function onlineVersionsFromScratch(cachePath, remotePackagesUrl) {
  if (!syncGetWorker) {
    return new Map();
  }

  const onlineVersionsJson = syncGetWorker.get(remotePackagesUrl);
  FS.mkdirpSync(path.dirname(cachePath));
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

/**
 * Compares two versions so that newer versions appear first when sorting with this function.
 *
 * @param {string} a
 * @param {string} b
 * @returns {number}
 */
function flippedSemverCompare(a, b) {
  const vA = a.split('.');
  const vB = b.split('.');
  return (
    compareNumber(vA[0], vB[0]) ||
    compareNumber(vA[1], vB[1]) ||
    compareNumber(vA[2], vB[2])
  );
}

/**
 * Compare 2 numbers as string
 *
 * @param {string} a
 * @param {string} b
 * @returns {number}
 */
function compareNumber(a, b) {
  return Number.parseInt(b, 10) - Number.parseInt(a, 10);
}

/**
 * @param {unknown} json
 * @returns {Map<string, string[]>}
 */
function parseOnlineVersions(json) {
  if (typeof json !== 'object' || json === null || Array.isArray(json)) {
    throw new Error(
      `Expected an object, but got: ${
        json === null ? 'null' : Array.isArray(json) ? 'Array' : typeof json
      }`
    );
  }

  /** @type {Map<string, string[]>} */
  const result = new Map();

  for (const [key, value] of Object.entries(json)) {
    result.set(key, parseVersions(key, value));
  }

  return result;
}

/**
 * @param {string} key
 * @param {unknown} json
 * @returns {string[]}
 */
function parseVersions(key, json) {
  if (!Array.isArray(json)) {
    throw new TypeError(
      `Expected ${JSON.stringify(key)} to be an array, but got: ${typeof json}`
    );
  }

  for (const [index, item] of json.entries()) {
    if (typeof item !== 'string') {
      throw new TypeError(
        `Expected${JSON.stringify(
          key
        )}->${index} to be a string, but got: ${typeof item}`
      );
    }
  }

  const castedJson = /** @type {string[]} */ (json);

  return castedJson;
}

/**
 * Cache in which we'll store information related Elm dependencies, computed by elm-solve-deps-wasm.
 *
 * @param {string} packageJsonVersion
 * @param {VersionString} elmVersion
 * @returns {Path}
 */
function dependenciesCachePath(packageJsonVersion, elmVersion) {
  return path.join(
    ProjectJsonFiles.elmHomeCache(packageJsonVersion),
    elmVersion,
    'versions-cache.json'
  );
}

/**
 * @param {string} pkg
 * @param {string} version
 * @returns {string}
 */
function remoteElmJsonUrl(pkg, version) {
  return `https://package.elm-lang.org/packages/${pkg}/${version}/elm.json`;
}

/**
 * @param {string} str
 * @returns {{pkg: string, version: string}}
 */
function splitPkgVersion(str) {
  const [pkg, version] = str.split('@');
  return {pkg, version};
}

/**
 * Enforces respecting pinned indirect dependencies.
 *
 * When Elm apps have pinned indirect versions, e.g.:
 *
 * "indirect": {
 *   "elm/virtual-dom": "1.0.3"
 * }
 *
 * We must prioritize these versions for the wasm dependency solver.
 *
 * Otherwise the wasm solver will take liberties that will result in
 * tests running with dependency versions distinct from those used by
 * the real live application.
 *
 * Assumes versions is sorted descending (newest -> oldest).
 *
 * @param {Array<string>} versions
 * @param {void | string} pinnedVersion
 * @returns {Array<string>}
 */
function prioritizePinnedIndirectVersion(versions, pinnedVersion) {
  if (pinnedVersion === undefined || !versions.includes(pinnedVersion)) {
    return versions;
  }

  // The pinned version and any newer version, in ascending order
  const desirableVersions = versions
    .filter((v) => v >= pinnedVersion)
    .reverse();

  // Older versions, in descending order
  const olderVersions = versions.filter((v) => v < pinnedVersion);

  return [...desirableVersions, ...olderVersions];
}

module.exports = {DependencyProvider, prioritizePinnedIndirectVersion};

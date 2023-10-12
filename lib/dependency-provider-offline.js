const fs = require('fs');
const os = require('os');
const path = require('path');
const process = require('process');

module.exports = {
  fetchElmJson,
  listAvailableVersions
};

// FetchElmJson(pkg: &str, version: &str) -> String;
function fetchElmJson(pkg, version) {
  // Console.log("Fetching: " + pkg + " @ " + version);
  try {
    return fs.readFileSync(homeElmJsonPath(pkg, version), 'utf8');
  } catch (_) {
    try {
      return fs.readFileSync(cacheElmJsonPath(pkg, version), 'utf8');
    } catch (_) {
      const remoteUrl = remoteElmJsonUrl(pkg, version);
      throw `Not doing a remote request to ${remoteUrl}. Please run at least once elm-test first.`;
    }
  }
}

const listAvailableVersionsCache = new Map();

// ListAvailableVersions(pkg: &str) -> Vec<JsValue>;
function listAvailableVersions(pkg) {
  if (listAvailableVersionsCache.has(pkg)) {
    return listAvailableVersionsCache.get(pkg);
  }

  try {
    // Reverse order of subdirectories to have newest versions first.
    const dependencies = fs.readdirSync(homePkgPath(pkg)).reverse();
    listAvailableVersionsCache.set(pkg, dependencies);
    return dependencies;
  } catch (_) {
    console.log(`Directory "${homePkgPath(pkg)} does not exist`);
    console.log(
      `Not doing a request to the package server to find out existing versions. Please run at least once elm-test first.`
    );
    return [];
  }
}

// Helper functions ##################################################

function remoteElmJsonUrl(pkg, version) {
  return `https://package.elm-lang.org/packages/${pkg}/${version}/elm.json`;
}

function cacheElmJsonPath(pkg, version) {
  const parts = splitAuthorPkg(pkg);
  return path.join(
    elmHome(),
    'pubgrub',
    'elm_json_cache',
    parts.author,
    parts.pkg,
    version,
    'elm.json'
  );
}

function homeElmJsonPath(pkg, version) {
  return path.join(homePkgPath(pkg), version, 'elm.json');
}

function homePkgPath(pkg) {
  const parts = splitAuthorPkg(pkg);
  return path.join(elmHome(), '0.19.1', 'packages', parts.author, parts.pkg);
}

function splitAuthorPkg(pkgIdentifier) {
  const parts = pkgIdentifier.split('/');
  return {author: parts[0], pkg: parts[1]};
}

function elmHome() {
  const elmHomeEnv = process.env.ELM_HOME;
  return elmHomeEnv ? elmHomeEnv : defaultElmHome();
}

function defaultElmHome() {
  return process.platform === 'win32'
    ? defaultWindowsElmHome()
    : defaultUnixElmHome();
}

function defaultUnixElmHome() {
  return path.join(os.homedir(), '.elm');
}

function defaultWindowsElmHome() {
  return path.join(process.env.APPDATA, 'elm');
}

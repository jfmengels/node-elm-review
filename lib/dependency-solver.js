const elmSolveDeps = require('elm-solve-deps-wasm');
const depsProvider = require('./dependency-provider-offline');

module.exports = {
  addExact
};

function addExact(options, elmJson, dependency, version) {
  initElmSolveDeps();

  let dependencies;

  dependencies = elmSolveDeps.solve_deps(
    elmJson,
    false,
    {[dependency]: `${version} <= v < ${nextPatchVersion(version)}`},
    depsProvider.fetchElmJson,
    depsProvider.listAvailableVersions
  );
  return JSON.parse(dependencies);
}

let elmSolveDepsWasInitialized = false;
function initElmSolveDeps() {
  if (!elmSolveDepsWasInitialized) {
    elmSolveDepsWasInitialized = true;
    elmSolveDeps.init();
  }
}

function nextPatchVersion(version) {
  const [major, minor, patch] = version.split('.');
  return `${major}.${minor}.${parseInt(patch, 10) + 1}`;
}

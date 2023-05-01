/**
 * @typedef { import("./types/path").Path } Path
 */

/**
 * @param {Path} path_
 * @returns {Path}
 */
function makePathOsAgnostic(path_) {
  return path_.replace(/.:/, '').replace(/\\/g, '/');
}

module.exports = {
  makePathOsAgnostic
};

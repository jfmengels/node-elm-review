/**
 * @file This module aims to make the paths and versions used in the CLI generic,
 * so that the CLI tests (in the `test/` folder) have the same output on different
 * machines, and also the same output when only the CLI version changes.
 */

/**
 * @import {Options} from './types/options';
 * @import {Path} from './types/path';
 */

const nPath = require('node:path');
const path = require('pathe');

/**
 * Strip the version and paths out of the given string.
 * This is only used for tests to make them pass even when the version/paths change.
 *
 * @param {Options} options
 * @param {string} string
 * @returns {string}
 */
function pathsAndVersions(options, string) {
  if (options.forTests) {
    const root = path.dirname(__dirname);
    const nRoot = nPath.dirname(__dirname);
    return replaceVersion(
      string.split(nRoot).join('<local-path>').split(root).join('<local-path>')
    );
  }

  return string;
}

/**
 * Strip the paths out of the given string.
 * This is only used for tests to make them pass even when it's run on different machines.
 *
 * @param {Options} options
 * @param {Path} filePath
 * @returns {Path}
 */
function anonymizePath(options, filePath) {
  if (options.forTests) {
    return replaceVersion(path.relative(options.cwd, filePath));
  }

  return filePath;
}

/**
 * Strip the version out of the given string.
 * This is only used for tests to make them pass even when the version changes.
 *
 * @param {string} string
 * @returns {string}
 */
function replaceVersion(string) {
  const packageJson = require('../package.json');
  return string.split(packageJson.version).join('<version>');
}

/**
 * Get the version to print to the user.
 *
 * @param {Options} options
 * @returns {string}
 */
function version(options) {
  if (options.forTests) {
    return '<version>';
  }

  return options.packageJsonVersion;
}

module.exports = {
  pathsAndVersions,
  path: anonymizePath,
  version
};

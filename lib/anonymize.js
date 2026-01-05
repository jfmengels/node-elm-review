/**
 * @file This module aims to make the paths and versions used in the CLI generic,
 * so that the CLI tests (in the `test/` folder) have the same output on different
 * machines, and also the same output when only the CLI version changes.
 */

/**
 * @import {Options} from './types/options';
 * @import {Path} from './types/path';
 */

const path = require('node:path');

/**
 * Strip the version and paths out of the given string.
 * This is only used for tests to make them pass even when the version/paths change.
 *
 * @param {string} string
 * @param {boolean} isTesting
 * @returns {string}
 */
function pathsAndVersions(string, isTesting) {
  if (isTesting) {
    const root = path.dirname(__dirname);
    return replaceVersion(string.split(root).join('<local-path>'));
  }

  return string;
}

/**
 * Convert DOS paths to POSIX paths.
 *
 * @param {string} string
 * @param {boolean} isTesting
 * @returns {string}
 */
function anonymizePaths(string, isTesting) {
  if (isTesting && process.platform === 'win32') {
    return (
      string
        // Strip Windows drive letters
        .replace(/[A-Z]:\\/g, '')

        // Shield JSON escapes so they survive path normalization
        .replace(/\\n/g, '__ESC_N__')
        .replace(/\\"/g, '__ESC_QUOTE__')

        // Normalize JSON escaped forward slashes
        .replace(/\\\//g, '/')

        // Normalize Windows path separators
        .replace(/\\\\/g, '/')
        .replace(/\\/g, '/')

        // Collapse duplicate slashes, except after URL schemes
        .replace(/(?<!:)\/{2,}/g, '/')

        // Restore JSON escapes
        .replace(/__ESC_N__/g, '\\n')
        .replace(/__ESC_QUOTE__/g, '\\"')

        // Human-mode prompt normalization
        .replace(/\(Y\\n\)/g, '(Y/n)')
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
  paths: anonymizePaths,
  version
};

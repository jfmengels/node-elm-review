/*
This module aims to make the paths and versions used in the CLI generic
so that the CLI tests (in the `test/` folder) have the same output on different
machines, and also the same output when only the CLI version changes.
*/

const path = require('path');

module.exports = {
  pathsAndVersions,
  path: anonymizePath,
  version
};

function pathsAndVersions(options, string) {
  if (options.forTests) {
    return replaceVersion(string.split(process.cwd()).join('<local-path>'));
  }

  return string;
}

function anonymizePath(options, filePath) {
  if (options.forTests) {
    return replaceVersion(path.relative(process.cwd(), filePath));
  }

  return filePath;
}

function replaceVersion(string) {
  const packageJson = require('../package.json');
  return string.split(packageJson.version).join('<version>');
}

function version(options) {
  if (options.forTests) {
    return '<version>';
  }

  return options.packageJsonVersion;
}

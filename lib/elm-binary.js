const path = require('path');
const util = require('util');
const which = require('which');
const spawn = require('cross-spawn');

function getElmBinary(options) {
  const whichAsync = util.promisify(which);
  if (options.compiler === undefined) {
    return whichAsync('elm').catch(() => {
      throw new Error(
        `Cannot find elm executable, make sure it is installed.
        (If elm is not on your path or is called something different the --compiler flag might help.)`
      );
    });
  }

  return whichAsync(path.resolve(options.compiler)).catch(() => {
    throw new Error(
      'The --compiler option must be given a path to an elm executable.'
    );
  });
}

async function getElmVersion(elmBinary) {
  const result = spawn.sync(elmBinary, ['--version'], {
    silent: true,
    env: process.env
  });

  if (result.status !== 0) {
    return '0.19.1';
  }

  return trimVersion(result.stdout.toString());
}

function trimVersion(version) {
  const index = version.indexOf('-');
  if (index === -1) {
    return version.trim();
  }

  return version.slice(0, index).trim();
}

module.exports = {
  getElmBinary,
  getElmVersion
};

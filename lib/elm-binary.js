const path = require('path');
const util = require('util');
const chalk = require('chalk');
const which = require('which');
const spawn = require('cross-spawn');
const ErrorMessage = require('./error-message');

function getElmBinary(options) {
  const whichAsync = util.promisify(which);
  if (options.compiler === undefined) {
    return whichAsync('elm').catch(() => {
      throw new ErrorMessage.CustomError(
        /* eslint-disable prettier/prettier */
'ELM NOT FOUND',
`I could not find the executable for the ${chalk.magentaBright('elm')} compiler.

A few options:
- Install it globally
- Specify the path using ${chalk.cyan('--compiler <path-to-elm>')}`,
options.elmJsonPath
        /* eslint-enable prettier/prettier */
      );
    });
  }

  return whichAsync(path.resolve(options.compiler)).catch(() => {
    throw new ErrorMessage.CustomError(
      /* eslint-disable prettier/prettier */
'ELM NOT FOUND',
`I could not find the executable for the ${chalk.magentaBright('elm')} compiler at the location you specified:
  ${options.compiler}`,
options.elmJsonPath
      /* eslint-enable prettier/prettier */
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

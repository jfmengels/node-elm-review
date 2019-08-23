const path = require('path');
const util = require('util');
const which = require('which');

function getElmBinary(args) {
  const whichAsync = util.promisify(which);
  if (args.compiler === undefined) {
    return whichAsync('elm').catch(() => {
      throw new Error(
        `Cannot find elm executable, make sure it is installed.
        (If elm is not on your path or is called something different the --compiler flag might help.)`
      );
    });
  }

  return whichAsync(path.resolve(args.compiler)).catch(() => {
    throw new Error(
      'The --compiler option must be given a path to an elm executable.'
    );
  });
}

module.exports = getElmBinary;

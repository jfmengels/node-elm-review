const path = require('path');
const which = require('which');

function getElmBinary(args) {
  if (args.compiler === undefined) {
    try {
      return which.sync('elm');
    } catch (error) {
      throw new Error(
        `Cannot find elm executable, make sure it is installed.
(If elm is not on your path or is called something different the --compiler flag might help.)`
      );
    }
  }

  try {
    return which.sync(path.resolve(args.compiler));
  } catch (error) {
    throw new Error(
      'The --compiler option must be given a path to an elm executable.'
    );
  }
}

module.exports = getElmBinary;

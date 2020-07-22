const path = require('path');
const appState = require('./state');

const options = appState.getOptions();

if (options.debug) {
  module.exports = {
    log,
    path: (filePath) => {
      if (options.debugForTests) {
        return replaceVersion(path.relative(process.cwd(), filePath));
      }

      return filePath;
    },
    version: replaceVersion
  };
} else {
  module.exports = {
    log: () => {},
    path: (filePath) => filePath,
    version: (string) => string
  };
}

function log(message) {
  console.log(message);
}

function replaceVersion(string) {
  if (options.debugForTests) {
    const packageJson = require('../package.json');
    return string.split(packageJson.version).join('<version>');
  }

  return string;
}

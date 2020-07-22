const path = require('path');
const appState = require('./state');

const options = appState.getOptions();

function log(message) {
  console.log(message);
}

if (options.debug) {
  module.exports = {
    log,
    path: (filePath) => {
      if (options.debugForTests) {
        return path.relative(process.cwd(), filePath);
      }

      return filePath;
    }
  };
} else {
  module.exports = {
    log: () => {},
    path: (filePath) => filePath
  };
}

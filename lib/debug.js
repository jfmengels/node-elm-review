const appState = require('./state');

const options = appState.getOptions();

function log(message) {
  console.log(message);
}

if (options.debug) {
  module.exports = {
    log
  };
} else {
  module.exports = {
    log: () => {}
  };
}

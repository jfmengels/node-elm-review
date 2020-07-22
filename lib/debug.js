const appState = require('./state');

const options = appState.getOptions();

module.exports = {
  log
};

function log(message) {
  if (options.debug) {
    console.log(message);
  }
}

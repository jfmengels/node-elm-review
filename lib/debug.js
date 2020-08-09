const AppState = require('./state');

const options = AppState.getOptions();

module.exports = {
  log
};

function log(message) {
  if (options.debug) {
    console.log(message);
  }
}

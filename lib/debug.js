const AppState = require('./state');

const options = AppState.getOptions();

module.exports = {
  log
};

/**
 * @param {string} message
 */
function log(message) {
  if (options.debug) {
    console.log(message);
  }
}

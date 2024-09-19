const AppState = require('./state');

const options = AppState.getOptions();

/**
 * @param {string} message
 */
function log(message) {
  if (options.debug) {
    console.log(message);
  }
}

module.exports = {
  log
};

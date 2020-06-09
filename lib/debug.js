const appState = require('./state');

const options = appState.getOptions();

function debug(message) {
  console.log(message);
}

if (options.debug) {
  module.exports = debug;
} else {
  module.exports = () => {};
}

function makePathOsAgnostic(path_) {
  return path_.replace(/.:/, '').replace(/\\/g, '/');
}

module.exports = {
  format
};


/**
 * Format a path so that you can `cd` it.
 * @param {string} str
 * @returns {string}
 */
function format(str) {
  const regex = /(['\s"])/g;
  return str.replace(regex, '\\$1');
}
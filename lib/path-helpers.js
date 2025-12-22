/**
 * Format a path so that you can `cd` it.
 *
 * @param {string} path
 * @returns {string}
 */
function format(path) {
  if (process.platform === 'win32') return path;

  const regex = /([^\w%+,./:=@-])/g;
  return path.replace(regex, '\\$1');
}

module.exports = {
  format
};

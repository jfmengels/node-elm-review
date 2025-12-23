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

/**
 * Normalize a path to use forward slashes (Unix-style).
 * This ensures consistent path representation across platforms,
 * which is crucial for comparing file paths in suppression files.
 *
 * @param {string} filePath
 * @returns {string}
 */
function toUnixPath(filePath) {
  return filePath.replace(/\\/g, '/');
}

module.exports = {
  format,
  toUnixPath
};

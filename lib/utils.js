/**
 * @template T
 * @param {T[]} array
 * @returns {T[]}
 */
function unique(array) {
  return [...new Set(array)];
}

/**
 * Convert anything into an error.
 *
 * If it's already an error, do nothing.
 * Otherwise, wrap it in a generic error.
 *
 * @param {unknown} error
 * @returns {Error}
 */
function intoError(error) {
  return error instanceof Error ? error : new Error(String(error));
}

module.exports = {
  intoError,
  unique
};

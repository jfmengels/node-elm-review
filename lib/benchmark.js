/**
 * @import {Options} from "./types/options"
 */

module.exports = {
  start,
  end
};

/**
 * Start a benchmark labelled with the given name.
 *
 * @param {Options} options
 * @param {string} name
 * @returns {void}
 */
function start(options, name) {
  if (options.showBenchmark) {
    console.time(name);
  }
}

/**
 * End a benchmark labelled with the given name.
 *
 * @param {Options} options
 * @param {string} name
 * @returns {void}
 */
function end(options, name) {
  if (options.showBenchmark) {
    console.timeEnd(name);
  }
}

/**
 * @import {OptionsBase} from './types/options';
 */

/**
 * Start a benchmark labelled with the given name.
 *
 * @param {OptionsBase} options
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
 * @param {OptionsBase} options
 * @param {string} name
 * @returns {void}
 */
function end(options, name) {
  if (options.showBenchmark) {
    console.timeEnd(name);
  }
}

module.exports = {
  start,
  end
};

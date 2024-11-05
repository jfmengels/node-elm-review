/**
 * Port of `elm/core` primitives to TS.
 * Enables functional-style programming without having to pull in `Effect.TS`.
 */

/**
 * @import {Err, Ok, Result} from './types/core';
 */

const {intoError} = require('./utils');

const result = {
  /**
   * Create a successful result.
   *
   * @template Value
   *
   * @param {Value} value
   * @returns {Ok<Value>}
   */
  succeed(value) {
    return {tag: 'ok', value};
  },

  /**
   * Create a failed result.
   *
   * @template Error
   *
   * @param {Error} error
   * @returns {Err<Error>}
   */
  fail(error) {
    return {tag: 'err', error};
  },

  /**
   * Returns the value of a result, or throws if in an errored state.
   *
   * @remarks
   * Converts errors into {@linkcode Error}s before throwing.
   * For more details, see {@linkcode intoError}.
   *
   * @template Value
   *
   * @param {Result<unknown, Value>} value
   * @returns {Value}
   * @throws {Error}
   */
  orThrow(value) {
    if (value.tag === 'ok') {
      return value.value;
    }

    throw intoError(value.error);
  }
};

module.exports = {
  result
};

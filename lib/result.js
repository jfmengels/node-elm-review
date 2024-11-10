/**
 * Port of `elm/core` primitives to TS.
 * Enables functional-style programming without having to pull in `Effect.TS`.
 */

/**
 * @import {Fail, Success, Result} from './types/result';
 */

const {intoError} = require('./utils');

/**
 * Create a successful result.
 *
 * @template Value
 *
 * @param {Value} value
 * @returns {Success<Value>}
 */
function succeed(value) {
  return {tag: 'ok', value};
}

/**
 * Create a failed result.
 *
 * @template Failure
 *
 * @param {Failure} failure
 * @returns {Fail<Failure>}
 */
function fail(failure) {
  return {tag: 'fail', failure};
}

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
function orThrow(value) {
  if (value.tag === 'ok') {
    return value.value;
  }

  throw intoError(value.failure);
}

module.exports = {
  succeed,
  fail,
  orThrow
};

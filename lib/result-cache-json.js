// @ts-expect-error(TS6133): There's a bug in noUnusedLocals (microsoft/TypeScript#58368).
/** @import {Replacer, Reviver} from './types/json'; */
// @ts-expect-error(TS6133): There's a bug in noUnusedLocals (microsoft/TypeScript#58368).
/** @import {ElmArray, Value, ValueStruct} from './types/elm-internals'; */

/** @type {Replacer} */
function replacer(_key, value_) {
  const value = /** @type {Value} */ (value_);

  if (value === null) {
    return value;
  }

  if (typeof value === 'object') {
    // TODO(@jfmengels): Also support serializing `Dict`s.
    // if (value.$ === -1) {
    //   return {
    //     $: '$D',
    //     a: toDictProd(value, {})
    //   };
    // }

    if (
      value.$ === 1 &&
      value.a !== undefined &&
      value.b !== undefined &&
      value.c === undefined
    ) {
      const list = prudentListToArray(value);
      if (list === null) {
        return value;
      }

      return {
        $: '$L',
        a: list
      };
    }

    return value;
  }

  if (Number.isNaN(value)) {
    return '$$elm-review$$NaN';
  }

  if (typeof value !== 'number' || Number.isFinite(value)) {
    return value;
  }

  if (value < 0) {
    return '$$elm-review$$-Inf';
  }

  return '$$elm-review$$+Inf';
}

/**
 * @param {ValueStruct} xs
 * @returns {ElmArray[] | null}
 */
function prudentListToArray(xs) {
  const out = [];
  for (; xs.b; xs = xs.b) {
    if (xs.a === undefined || xs.c !== undefined) {
      return null;
    }

    out.push(xs.a);
  }

  if (xs.$ !== 0 || xs.a !== undefined) {
    return null;
  }

  return out;
}

/** @type {Reviver} */
function reviver(_, value_) {
  const value = /** @type {Value} */ (value_);

  if (
    typeof value === 'object' &&
    /** @type {SomethingObject} */ value?.$ === '$L'
  ) {
    return _ListFromArrayPROD(/** @type {string | string[]} */ (value.a));
  }

  if (typeof value !== 'string' || !value?.startsWith('$$elm-review$$')) {
    return value;
  }

  switch (value.slice(14)) {
    case 'NaN': {
      return Number.NaN;
    }

    case '+Inf': {
      return Number.POSITIVE_INFINITY;
    }

    case '-Inf': {
      return Number.NEGATIVE_INFINITY;
    }

    default: {
      return value;
    }
  }
}

/** @type {ValueStruct} */
const _ListNilPROD = {$: 0};

/**
 * @param {ElmArray} array
 * @returns {ValueStruct}
 */
function _ListFromArrayPROD(array) {
  let out = _ListNilPROD;
  for (let i = array.length; i--; ) {
    out = {$: 1, a: array[i], b: out};
  }

  return out;
}

module.exports = {
  replacer,
  reviver
};

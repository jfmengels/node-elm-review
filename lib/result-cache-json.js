module.exports = {
  replacer,
  reviver
};

function replacer(key, value) {
  if (typeof value === 'object') {
    // TODO Serialize Dicts also
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
      const list = prudent_List_toArray(value);
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


function prudent_List_toArray(xs) {
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

function reviver(_, value) {
  const type_ = typeof value;
  if (type_ === 'object' && value.$ === '$L') {
    return _List_fromArray_PROD(value.a);
  }

  if (
    type_ !== 'string' ||
    value === null ||
    !value.startsWith('$$elm-review$$')
  ) {
    return value;
  }

  switch (value.slice(14)) {
    case 'NaN':
      return Number.NaN;
    case '+Inf':
      return Infinity;
    case '-Inf':
      return -Infinity;
    default:
      return value;
  }
}

const _List_Nil_PROD = {$: 0};
function _List_fromArray_PROD(array) {
  let out = _List_Nil_PROD;
  for (let i = array.length; i--; ) {
    out = {$: 1, a: array[i], b: out};
  }

  return out;
}

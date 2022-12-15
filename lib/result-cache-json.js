module.exports = {
  replacer,
  reviver
};

function replacer(key, value) {
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

function reviver(_, value) {
  if (
    typeof value !== 'string' ||
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

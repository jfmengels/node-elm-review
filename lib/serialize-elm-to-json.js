const debugData = {
  listOfStrings: {
    $: '::',
    a: 'listOfStrings',
    b: {
      $: '::',
      a: 'a',
      b: {
        $: '::',
        a: 'b',
        b: {$: '::', a: 'c', b: {$: '::', a: 'd', b: {$: '[]'}}}
      }
    }
  }
};

const optimizedData = {"$":1,"a":"listOfStrings","b":{"$":1,"a":"a1","b":{"$":1,"a":"a2","b":{"$":1,"a":"a2","b":{"$":1,"a":"a2","b":{"$":0}}}}}};

function replacer(options) {
  if (options.debug) {
    return debugReplacer;
  }
  return optimizedReplacer;
}

function debugReplacer(key, value) {
  console.log({key}, value);
  if (value.$ === "::") {
    return {
      $: 'LIST',
      a: _List_toArray(value)
    };
  }
  return value;
}

function optimizedReplacer(key, value) {
  if (value.$ === 1 && value.a !== undefined && value.b !== undefined && value.c === undefined) {
    const list = prudent_List_toArray(value);
    if (list === null) {
      return value;
    }
    return {
      $: 'LIST',
      a: list
    };
  }

  return value;
}

function _List_toArray(xs)
{
  const out = [];
  for (; xs.b; xs = xs.b) // WHILE_CONS
  {
    out.push(xs.a);
  }
  return out;
}

function prudent_List_toArray(xs)
{
  const out = [];
  for (; xs.b; xs = xs.b) // WHILE_CONS
  {
    // TODO check if we need to do anything more to make sure we don't mess up.
    if (xs.a === undefined || xs.c !== undefined) {
      return null;
    }
    out.push(xs.a);
  }
  return out;
}

function reviver(options) {
  return (key, value) => {
    console.log({key, value})
    return value;
  }
}

const options = {
  debug: true
};

// console.log(JSON.stringify(debugData, replacer));
console.log(JSON.parse(JSON.stringify(debugData, replacer(options)), reviver(options)));
console.log()
console.log()
// console.log(JSON.stringify(optimizedData, replacer(options)));
// console.log(JSON.parse(JSON.stringify(optimizedData, replacer(options)), reviver(options)));


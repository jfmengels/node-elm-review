function replacer(options) {
  if (options.debug) {
    return debugReplacer;
  }
  return optimizedReplacer;
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

function debugReplacer(key, value) {
  if (value.$ === "::") {
    return {
      $: 'LIST',
      a: _List_toArray(value)
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
      console.log('stop')

      return null;
    }
    out.push(xs.a);
  }
  if (xs.$ !== 0 || xs.a !== undefined) {
    return null;
  }

  return out;
}

function reviver(options) {
  if (options.debug) {
    return debugReviver;
  }
  return optimizedReviver;
}

function optimizedReviver(key, value) {
  if (value.$ === 'LIST') {
    return _List_fromArray_PROD(value.a);
  }
  return value;
}

function debugReviver(key, value) {
  if (value.$ === 'LIST') {
    return _List_fromArray_DEBUG(value.a);
  }
  return value;
}

function _List_fromArray_PROD(arr)
{
  var out = { $: 0 };
  for (var i = arr.length; i--; )
  {
    out = { $: 1, a: arr[i], b: out };
  }
  return out;
}

function _List_fromArray_DEBUG(arr)
{
  var out = { $: '[]' };
  for (var i = arr.length; i--; )
  {
    out = { $: '::', a: arr[i], b: out };
  }
  return out;
}

//////////////////////////////////////////////


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

const optimizedData = {"$":1,"a":"listOfStrings","b":{"$":1,"a":"a","b":{"$":1,"a":"b","b":{"$":1,"a":"c","b":{"$":1,"a":"d","b":{"$":0}}}}}};


function test(options, data) {
  console.log("#### BEFORE\n")
  console.log(data);

  console.log("\n#### JSON\n")
  const json = JSON.stringify(data, replacer(options));
  console.log(json);

  console.log("\n#### AFTER\n")
  console.log(JSON.parse(json, reviver(options)));
}


console.log("######################## DEBUG\n")
test({debug: true}, debugData)
console.log("######################## PROD\n")
test({debug: false}, optimizedData)
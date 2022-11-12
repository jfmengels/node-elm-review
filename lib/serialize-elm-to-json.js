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

function replacer(key, value) {
  console.log({key}, value);
  if (value.$ === "::") {
    return {
      $: 'LIST',
      a: _List_toArray(value)
    };
  }

  if (value.$ === 1 && value.a !== undefined && value.b !== undefined && value.c === undefined) {
    var list = prudent_List_toArray(value);
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
  for (var out = []; xs.b; xs = xs.b) // WHILE_CONS
  {
    out.push(xs.a);
  }
  return out;
}

function prudent_List_toArray(xs)
{
  for (var out = []; xs.b; xs = xs.b) // WHILE_CONS
  {
    // TODO check if we need to do anything more to make sure we don't mess up.
    if (xs.a === undefined || xs.c !== undefined) {
      return null;
    }
    out.push(xs.a);
  }
  return out;
}

console.log(JSON.stringify(debugData, replacer));
console.log()
console.log()
console.log(JSON.stringify(optimizedData, replacer));


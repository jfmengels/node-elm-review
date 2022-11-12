module.exports = {
  stringify: (options, data) =>
    JSON.stringify(data, replacer(options), options.debug ? 2 : 0),
  parse: (options, data) =>
    JSON.stringify(data, reviver(options), options.debug ? 2 : 0),
  replacer,
  reviver
};

function replacer(options) {
  if (options.debug) {
    return debugReplacer;
  }

  return optimizedReplacer;
}

function optimizedReplacer(key, value) {
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
      $: 'LIST',
      a: list
    };
  }

  return value;
}

function debugReplacer(key, value) {
  if (value.$ === '::') {
    return {
      $: 'LIST',
      a: _List_toArray(value)
    };
  }

  return value;
}

function _List_toArray(xs) {
  const out = [];
  for (
    ;
    xs.b;
    xs = xs.b // WHILE_CONS
  ) {
    out.push(xs.a);
  }

  return out;
}

function prudent_List_toArray(xs) {
  const out = [];
  for (
    ;
    xs.b;
    xs = xs.b // WHILE_CONS
  ) {
    // TODO check if we need to do anything more to make sure we don't mess up.
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

function _List_fromArray_PROD(array) {
  let out = {$: 0};
  for (let i = array.length; i--; ) {
    out = {$: 1, a: array[i], b: out};
  }

  return out;
}

function _List_fromArray_DEBUG(array) {
  let out = {$: '[]'};
  for (let i = array.length; i--; ) {
    out = {$: '::', a: array[i], b: out};
  }

  return out;
}

/// ///////////////////////////////////////////

// const debugData = {
//   listOfStrings: {
//     $: '::',
//     a: 'listOfStrings',
//     b: {
//       $: '::',
//       a: 'a',
//       b: {
//         $: '::',
//         a: 'b',
//         b: {$: '::', a: 'c', b: {$: '::', a: 'd', b: {$: '[]'}}}
//       }
//     }
//   }
// };
//
// const optimizedData = {"$":1,"a":"listOfStrings","b":{"$":1,"a":"a","b":{"$":1,"a":"b","b":{"$":1,"a":"c","b":{"$":1,"a":"d","b":{"$":0}}}}}};
//
//
// function test(options, data) {
//   console.log("#### BEFORE\n")
//   console.log(data);
//
//   console.log("\n#### JSON\n")
//   const json = JSON.stringify(data, replacer(options));
//   console.log(json);
//
//   console.log("\n#### AFTER\n")
//   console.log(JSON.parse(json, reviver(options)));
// }
//
//
// console.log("######################## DEBUG\n")
// test({debug: true}, debugData)
// console.log("######################## PROD\n")
// test({debug: false}, optimizedData)

const debugData = {
  _char: 'b',
  dictOfThings: {
    $: 'RBNode_elm_builtin',
    a: {
      $: 'Black'
    },
    b: 'dictOfThings2',
    c: 12,
    d: {
      $: 'RBNode_elm_builtin',
      a: {
        $: 'Black'
      },
      b: 'dictOfThings',
      c: 123456789,
      d: {
        $: 'RBEmpty_elm_builtin'
      },
      e: {
        $: 'RBEmpty_elm_builtin'
      }
    },
    e: {
      $: 'RBNode_elm_builtin',
      a: {
        $: 'Black'
      },
      b: 'dictOfThings3',
      c: 90,
      d: {
        $: 'RBEmpty_elm_builtin'
      },
      e: {
        $: 'RBEmpty_elm_builtin'
      }
    }
  },
  exposedModules: {
    $: 'Set_elm_builtin',
    a: {
      $: 'RBEmpty_elm_builtin'
    }
  },
  fileLinksAndSections: {
    $: 'LIST',
    a: [
      {
        fileKey: {
          $: 'ModuleKey',
          a: {
            $: 'ModuleKey',
            a: 'src/Page/Article/Editor.elm'
          }
        },
        links: {
          $: '[]'
        },
        moduleName: {
          $: 'LIST',
          a: ['Page', 'Article', 'Editor']
        },
        sections: {
          $: 'LIST',
          a: [
            {
              isExposed: true,
              slug: 'Model'
            },
            {
              isExposed: true,
              slug: 'Msg'
            },
            {
              isExposed: true,
              slug: 'initEdit'
            },
            {
              isExposed: true,
              slug: 'initNew'
            },
            {
              isExposed: true,
              slug: 'subscriptions'
            },
            {
              isExposed: true,
              slug: 'toSession'
            },
            {
              isExposed: true,
              slug: 'update'
            },
            {
              isExposed: true,
              slug: 'view'
            }
          ]
        }
      }
    ]
  },
  listOfStrings: {
    $: '[]'
  },
  packageNameAndVersion: {
    $: 'Nothing'
  }
};

const optimizedData = {
  b6: 'b',
  bc: {
    $: -1,
    a: 1,
    b: 'dictOfThings2',
    c: 12,
    d: {$: -1, a: 1, b: 'dictOfThings', c: 123456789, d: {$: -2}, e: {$: -2}},
    e: {$: -1, a: 1, b: 'dictOfThings3', c: 90, d: {$: -2}, e: {$: -2}}
  },
  da: {$: -2},
  aI: {
    $: 'LIST',
    a: [
      {
        a$: {$: 0, a: 'src/Page/Blank.elm'},
        C: {$: 0},
        cn: {$: 'LIST', a: ['Page', 'Blank']},
        ax: {$: 'LIST', a: [{aK: true, a6: 'view'}]}
      }
    ]
  },
  cU: {$: 0},
  aQ: {$: 1}
};

function test(options, data) {
  console.log('#### BEFORE\n');
  console.log(data);

  console.log('\n#### JSON\n');
  const json = JSON.stringify(data, replacer(options));
  console.log(json);

  console.log('\n#### AFTER\n');
  console.log(JSON.parse(json, reviver(options)));
}

console.log('######################## DEBUG\n');
test({debug: true}, debugData);
console.log('######################## PROD\n');
test({debug: false}, optimizedData);

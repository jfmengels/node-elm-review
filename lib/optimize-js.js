/**
 * @import {Options} from './types/options';
 * @import {Optimization} from './types/optimize-js';
 */

const Benchmark = require('./benchmark');
const FS = require('./fs-wrapper');

/**
 * @param {Options} options
 * @param {string | null} elmModulePath
 * @param {boolean} isReviewApp
 * @returns {Promise<string | null>}
 */
async function optimize(options, elmModulePath, isReviewApp) {
  if (options.debug || !elmModulePath) {
    return elmModulePath;
  }

  const timerId = isReviewApp
    ? 'optimizing review application'
    : 'optimizing parser application';
  Benchmark.start(options, timerId);
  const originalSource = await FS.readFile(elmModulePath);
  const replacements = isReviewApp
    ? [
        ...performanceReplacements,
        ...cacheReplacements(options.localElmReviewSrc)
      ]
    : performanceReplacements;

  const newSource = replacements
    .reduce((source, {target, replacement}) => {
      return source.replace(target, replacement);
    }, originalSource)
    .replace(
      /var ([\w$]+) = F(\d)\(\s*function\s*\(/g,
      'var $1 = F$2(function $1$fn('
    );

  await FS.writeFile(elmModulePath, newSource);
  Benchmark.end(options, timerId);
  return elmModulePath;
}

const performanceReplacements = [
  {
    target: `var $elm$core$List$all = F2(
\tfunction (isOkay, list) {
\t\treturn !A2(
\t\t\t$elm$core$List$any,
\t\t\tA2($elm$core$Basics$composeL, $elm$core$Basics$not, isOkay),
\t\t\tlist);
\t});`,
    replacement: `var $elm$core$List$all = F2(function (isOkay, list) {
  all: while (true) {
    if (!list.b) {
      return true;
    }
    else {
      var x = list.a;
      if (!isOkay(x)) {
        return false;
      }
      list = list.b;
      continue all;
    }
  }
});`
  },
  {
    target: `var $elm$core$List$append = F2(
\tfunction (xs, ys) {
\t\tif (!ys.b) {
\t\t\treturn xs;
\t\t} else {
\t\t\treturn A3($elm$core$List$foldr, $elm$core$List$cons, ys, xs);
\t\t}
\t});`,
    replacement: `var $elm$core$List$append = F2(function (xs, ys) {
  var tmp = _List_Cons(undefined, _List_Nil);
  var end = tmp;
  for (; xs.b; xs = xs.b) {
    var next = _List_Cons(xs.a, _List_Nil);
    end.b = next;
    end = next;
  }
  end.b = ys;

  return tmp.b;
});`
  },
  {
    target: `var $elm$core$List$concat = function (lists) {
\treturn A3($elm$core$List$foldr, $elm$core$List$append, _List_Nil, lists);
};`,
    replacement: `var $elm$core$List$concat = function (lists) {
  if (!lists.b) {
    return _List_Nil;
  }
  var tmp = _List_Cons(undefined, _List_Nil);
  var end = tmp;
  for (; lists.b.b; lists = lists.b) {
    var xs = lists.a;
    for (; xs.b; xs = xs.b) {
      var next = _List_Cons(xs.a, _List_Nil);
      end.b = next;
      end = next;
    }
  }
  end.b = lists.a;

  return tmp.b;
};`
  },
  {
    target: `var $elm$core$List$concatMap = F2(
\tfunction (f, list) {
\t\treturn $elm$core$List$concat(
\t\t\tA2($elm$core$List$map, f, list));
\t});`,
    replacement: `var $elm$core$List$concatMap = F2(function (f, lists) {
  if (!lists.b) {
    return _List_Nil;
  }
  var tmp = _List_Cons(undefined, _List_Nil);
  var end = tmp;
  for (; lists.b.b; lists = lists.b) {
    var xs = f(lists.a);
    for (; xs.b; xs = xs.b) {
      var next = _List_Cons(xs.a, _List_Nil);
      end.b = next;
      end = next;
    }
  }
  end.b = f(lists.a);

  return tmp.b;
});`
  },
  {
    target: `var $elm$core$List$filter = F2(
\tfunction (isGood, list) {
\t\treturn A3(
\t\t\t$elm$core$List$foldr,
\t\t\tF2(
\t\t\t\tfunction (x, xs) {
\t\t\t\t\treturn isGood(x) ? A2($elm$core$List$cons, x, xs) : xs;
\t\t\t\t}),
\t\t\t_List_Nil,
\t\t\tlist);
\t});`,
    replacement: `var $elm$core$List$filter = F2(function (f, xs) {
  var tmp = _List_Cons(undefined, _List_Nil);
  var end = tmp;
  for (; xs.b; xs = xs.b) {
    if (f(xs.a)) {
      var next = _List_Cons(xs.a, _List_Nil);
      end.b = next;
      end = next;
    }
  }
  return tmp.b;
});`
  },
  {
    target: `var $elm$core$List$indexedMap = F2(
\tfunction (f, xs) {
\t\treturn A3(
\t\t\t$elm$core$List$map2,
\t\t\tf,
\t\t\tA2(
\t\t\t\t$elm$core$List$range,
\t\t\t\t0,
\t\t\t\t$elm$core$List$length(xs) - 1),
\t\t\txs);
\t});`,
    replacement: `var $elm$core$List$indexedMap = F2(function (f, xs) {
  var tmp = _List_Cons(undefined, _List_Nil);
  var end = tmp;
  for (var i = 0; xs.b; i++, xs = xs.b) {
    var next = _List_Cons(A2(f, i, xs.a), _List_Nil);
    end.b = next;
    end = next;
  }
  return tmp.b;
});`
  },
  {
    target: `var $elm$core$List$intersperse = F2(
\tfunction (sep, xs) {
\t\tif (!xs.b) {
\t\t\treturn _List_Nil;
\t\t} else {
\t\t\tvar hd = xs.a;
\t\t\tvar tl = xs.b;
\t\t\tvar step = F2(
\t\t\t\tfunction (x, rest) {
\t\t\t\t\treturn A2(
\t\t\t\t\t\t$elm$core$List$cons,
\t\t\t\t\t\tsep,
\t\t\t\t\t\tA2($elm$core$List$cons, x, rest));
\t\t\t\t});
\t\t\tvar spersed = A3($elm$core$List$foldr, step, _List_Nil, tl);
\t\t\treturn A2($elm$core$List$cons, hd, spersed);
\t\t}
\t});`,
    replacement: `var $elm$core$List$intersperse = F2(function (sep, xs) {
  if (!xs.b) {
    return xs;
  }
  var tmp = _List_Cons(undefined, _List_Nil);
  var end = tmp;

  end.b = _List_Cons(xs.a, _List_Nil);
  end = end.b;
  xs = xs.b;

  for (; xs.b; xs = xs.b) {
    var valNode = _List_Cons(xs.a, _List_Nil);
    var sepNode = _List_Cons(sep, valNode);
    end.b = sepNode;
    end = valNode;
  }

  return tmp.b;
});`
  },
  {
    target: `var $elm$core$List$map = F2(
\tfunction (f, xs) {
\t\treturn A3(
\t\t\t$elm$core$List$foldr,
\t\t\tF2(
\t\t\t\tfunction (x, acc) {
\t\t\t\t\treturn A2(
\t\t\t\t\t\t$elm$core$List$cons,
\t\t\t\t\t\tf(x),
\t\t\t\t\t\tacc);
\t\t\t\t}),
\t\t\t_List_Nil,
\t\t\txs);
\t});`,
    replacement: `var $elm$core$List$map = F2(function (f, xs) {
  var tmp = _List_Cons(undefined, _List_Nil);
  var end = tmp;
  for (; xs.b; xs = xs.b) {
    var next = _List_Cons(f(xs.a), _List_Nil);
    end.b = next;
    end = next;
  }
  return tmp.b;
});`
  },
  {
    target: `var $elm$core$List$partition = F2(
\tfunction (pred, list) {
\t\tvar step = F2(
\t\t\tfunction (x, _v0) {
\t\t\t\tvar trues = _v0.a;
\t\t\t\tvar falses = _v0.b;
\t\t\t\treturn pred(x) ? _Utils_Tuple2(
\t\t\t\t\tA2($elm$core$List$cons, x, trues),
\t\t\t\t\tfalses) : _Utils_Tuple2(
\t\t\t\t\ttrues,
\t\t\t\t\tA2($elm$core$List$cons, x, falses));
\t\t\t});
\t\treturn A3(
\t\t\t$elm$core$List$foldr,
\t\t\tstep,
\t\t\t_Utils_Tuple2(_List_Nil, _List_Nil),
\t\t\tlist);
\t});`,
    replacement: `var $elm$core$List$partition = F2(function (f, xs) {
  var truesHead = _List_Cons(undefined, _List_Nil);
  var falsesHead = _List_Cons(undefined, _List_Nil);
  var truesEnd = truesHead;
  var falsesEnd = falsesHead;
  for (; xs.b; xs = xs.b) {
    var next = _List_Cons(xs.a, _List_Nil);
    if (f(xs.a)) {
      truesEnd.b = next;
      truesEnd = next;
    } else {
      falsesEnd.b = next;
      falsesEnd = next;
    }
  }
  return _Utils_Tuple2(truesHead.b, falsesHead.b);
});`
  },
  {
    target: `var $elm$core$List$take = F2(
\tfunction (n, list) {
\t\treturn A3($elm$core$List$takeFast, 0, n, list);
\t});`,
    replacement: `var $elm$core$List$take = F2(function(n, xs) {
  var tmp = _List_Cons(undefined, _List_Nil);
  var end = tmp;
  for (var i = 0; i < n && xs.b; xs = xs.b, i++) {
    var next = _List_Cons(xs.a, _List_Nil);
    end.b = next;
    end = next;
  }
  return tmp.b;
});`
  },
  {
    target: `var $elm$core$List$unzip = function (pairs) {
\tvar step = F2(
\t\tfunction (_v0, _v1) {
\t\t\tvar x = _v0.a;
\t\t\tvar y = _v0.b;
\t\t\tvar xs = _v1.a;
\t\t\tvar ys = _v1.b;
\t\t\treturn _Utils_Tuple2(
\t\t\t\tA2($elm$core$List$cons, x, xs),
\t\t\t\tA2($elm$core$List$cons, y, ys));
\t\t});
\treturn A3(
\t\t$elm$core$List$foldr,
\t\tstep,
\t\t_Utils_Tuple2(_List_Nil, _List_Nil),
\t\tpairs);
};`,
    replacement: `var $elm$core$List$unzip = function (pairs) {
  var aHead = _List_Cons(undefined, _List_Nil);
  var bHead = _List_Cons(undefined, _List_Nil);
  var aEnd = aHead;
  var bEnd = bHead;
  for (; pairs.b; pairs = pairs.b) {
    var tuple = pairs.a;

    var aNext = _List_Cons(tuple.a, _List_Nil);
    aEnd.b = aNext;
    aEnd = aNext;

    var bNext = _List_Cons(tuple.b, _List_Nil);
    bEnd.b = bNext;
    bEnd = bNext;
  }
  return _Utils_Tuple2(aHead.b, bHead.b);
};`
  },
  {
    target: `var $elm$core$List$filterMap = F2(
\tfunction (f, xs) {
\t\treturn A3(
\t\t\t$elm$core$List$foldr,
\t\t\t$elm$core$List$maybeCons(f),
\t\t\t_List_Nil,
\t\t\txs);
\t});`,
    replacement: `var $elm$core$List$filterMap = F2(function (f, xs) {
  var tmp = _List_Cons(undefined, _List_Nil);
  var end = tmp;
  for (; xs.b; xs = xs.b) {
    var m = f(xs.a);
    if (!m.$) {
      var next = _List_Cons(m.a, _List_Nil);
      end.b = next;
      end = next;
    }
  }
  return tmp.b;
});`
  },
  {
    target: `var $elm$core$Set$map = F2(
\tfunction (func, set) {
\t\treturn $elm$core$Set$fromList(
\t\t\tA3(
\t\t\t\t$elm$core$Set$foldl,
\t\t\t\tF2(
\t\t\t\t\tfunction (x, xs) {
\t\t\t\t\t\treturn A2(
\t\t\t\t\t\t\t$elm$core$List$cons,
\t\t\t\t\t\t\tfunc(x),
\t\t\t\t\t\t\txs);
\t\t\t\t\t}),
\t\t\t\t_List_Nil,
\t\t\t\tset));
\t});`,
    replacement: `var $elm$core$Set$map = F2(
  function (func, set) {
    return A3(
      $elm$core$Set$foldl,
      F2(
        function (x, acc) {
          return A2(
            $elm$core$Set$insert,
            func(x),
            acc);
        }),
      $elm$core$Set$empty,
      set);
  });`
  },
  {
    target: `var $elm$core$Basics$composeL = F3(
	function (g, f, x) {
		return g(
			f(x));
	});`,
    replacement: `var $elm$core$Basics$composeL = F2(function $elm$core$Basics$composeL$fn(g, f) {
  return function(x) {
    return g(f(x));
  };
});`
  },
  {
    target: `var $elm$core$Basics$composeR = F3(
	function (f, g, x) {
		return g(
			f(x));
	});`,
    replacement: `var $elm$core$Basics$composeR = F2(function $elm$core$Basics$composeR$fn(f, g) {
  return function(x) {
    return g(f(x));
  };
});`
  }
];

/**
 * @param {string | undefined} localElmReviewSrc
 * @returns {Optimization[]}
 */
function cacheReplacements(localElmReviewSrc) {
  const packageName = localElmReviewSrc
    ? '$author$project'
    : '$jfmengels$elm_review';
  return [
    {
      target: `var ${packageName}$Review$Rule$initialCacheMarker = F3(
\tfunction (_v0, _v1, cache) {
\t\treturn cache;
\t});`,
      replacement: `var ${packageName}$Review$Rule$initialCacheMarker = F3(
  function (ruleName, ruleId, defaultCache) {
    return globalThis.loadResultFromCache(ruleName, ruleId) || defaultCache;
  });`
    },
    {
      target: `var ${packageName}$Review$Rule$finalCacheMarker = F3(
\tfunction (_v0, _v1, cache) {
\t\treturn cache;
\t});`,
      replacement: `var ${packageName}$Review$Rule$finalCacheMarker = F3(
  function (ruleName, ruleId, cacheEntry) {
    globalThis.saveResultToCache(ruleName, ruleId, cacheEntry);
    return cacheEntry;
  });`
    },
    {
      target: `var ${packageName}$Review$Cache$ContextHash$createContextHashMarker = function (context) {
\treturn context;
};`,
      replacement: `var ${packageName}$Review$Cache$ContextHash$createContextHashMarker = function (context) {
  return jsonToHash(contextToJson(context));
};

const stringifyMap = new WeakMap();
function contextToJson(context) {
  const isObject = typeof context === 'object';
  if (!isObject) {
    return JSON.stringify(context);
  }
  if (stringifyMap.has(context)) {
    return stringifyMap.get(context);
  } else {
    const json = JSON.stringify(context, globalThis.elmJsonReplacer);
    stringifyMap.set(context, json);
    return json;
  }
}

const contextHashMap = new Map();
function jsonToHash(json) {
  if (contextHashMap.has(json)) {
    return contextHashMap.get(json);
  }
  const hash = A2(${packageName}$Vendor$Murmur3$hashString, 0, json);
  contextHashMap.set(json, hash);
  return hash;
}`
    },
    {
      target: `var ${packageName}$Review$Rule$createRuleModuleVisitor = F4(
\tfunction (schema, params, toRuleProjectVisitor, initialContext) {
\t\tvar raise = function (errorsAndContext) {
\t\t\treturn {`,
      replacement: `var ${packageName}$Review$Rule$createRuleModuleVisitor = F4(
  function (schema, params, toRuleProjectVisitor, initialContext) {
    var raise = function (errorsAndContext) {
      function raise(_v0) {
        errorsAndContext.a = _v0.a;
        errorsAndContext.b = _v0.b;
      }
      return {`
    },
    {
      target: `var ${packageName}$Review$Rule$fromJsArrayToList = function (_v0) {
\tvar list = _v0;
\treturn list;
};`,
      replacement: `var ${packageName}$Review$Rule$fromJsArrayToList = _List_fromArray;`
    },
    {
      target: `var ${packageName}$Review$Rule$fromListToJsArray = $elm$core$Basics$identity;`,
      replacement: `var ${packageName}$Review$Rule$fromListToJsArray = _List_toArray;`
    },
    {
      target: `var ${packageName}$Review$Rule$mutatingMap = F2(
\tfunction (mapper, _v0) {
\t\tvar list = _v0;
\t\treturn A2($elm$core$List$map, mapper, list);
\t});`,
      replacement: `var ${packageName}$Review$Rule$mutatingMap = F2(
  function (mapper, arr) {
    var len = arr.length;
    for (var i = 0; i < len; i++) {
      mapper(arr[i]);
    }
    return arr;
  });`
    },
    {
      target: `var ${packageName}$Review$Cache$ContextHash$sort = $elm$core$Basics$identity;`,
      replacement: `var ${packageName}$Review$Cache$ContextHash$sort = function(l) { return $elm$core$List$sort(l); }`
    }
  ];
}

module.exports = {
  optimize
};

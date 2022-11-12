const {F, F2, F3, F4, F5, F6, F7, F8, F9, A2, A3, A4, A5, A6, A7, A8, A9} = require('./a-f-functions');
const {$elm$core$Basics$EQ, $elm$core$Basics$GT, $elm$core$Basics$LT} = require('./basics');

var _Utils_compare = F2(function(x, y)
{
  var n = _Utils_cmp(x, y);
  return n < 0 ? $elm$core$Basics$LT : n ? $elm$core$Basics$GT : $elm$core$Basics$EQ;
});

function _Utils_cmp(x, y, ord)
{
  if (typeof x !== 'object')
  {
    return x === y ? /*EQ*/ 0 : x < y ? /*LT*/ -1 : /*GT*/ 1;
  }

  if (typeof x.$ === 'undefined')
  {
    return (ord = _Utils_cmp(x.a, y.a))
      ? ord
      : (ord = _Utils_cmp(x.b, y.b))
        ? ord
        : _Utils_cmp(x.c, y.c);
  }

  // traverse conses until end of a list or a mismatch
  for (; x.b && y.b && !(ord = _Utils_cmp(x.a, y.a)); x = x.b, y = y.b) {} // WHILE_CONSES
  return ord || (x.b ? /*GT*/ 1 : y.b ? /*LT*/ -1 : /*EQ*/ 0);
}

module.exports = {
  _Utils_compare
}
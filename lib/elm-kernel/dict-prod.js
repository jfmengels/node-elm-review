const {F3, F5, A2, A3, A5} = require('./a-f-functions');
const {_Utils_compare} = require('./utils');

var $elm$core$Dict$RBEmpty_elm_builtin = {$: -2};
var $elm$core$Dict$empty = $elm$core$Dict$RBEmpty_elm_builtin;
var $elm$core$Dict$RBNode_elm_builtin = F5(
  function (a, b, c, d, e) {
    return {$: -1, a: a, b: b, c: c, d: d, e: e};
  });
var $elm$core$Dict$balance = F5(
  function (color, key, value, left, right) {
    if ((right.$ === -1) && (!right.a)) {
      var rK = right.b;
      var rV = right.c;
      var rLeft = right.d;
      var rRight = right.e;
      if ((left.$ === -1) && (!left.a)) {
        var lK = left.b;
        var lV = left.c;
        var lLeft = left.d;
        var lRight = left.e;
        return A5(
          $elm$core$Dict$RBNode_elm_builtin,
          0,
          key,
          value,
          A5($elm$core$Dict$RBNode_elm_builtin, 1, lK, lV, lLeft, lRight),
          A5($elm$core$Dict$RBNode_elm_builtin, 1, rK, rV, rLeft, rRight));
      } else {
        return A5(
          $elm$core$Dict$RBNode_elm_builtin,
          color,
          rK,
          rV,
          A5($elm$core$Dict$RBNode_elm_builtin, 0, key, value, left, rLeft),
          rRight);
      }
    } else {
      if ((((left.$ === -1) && (!left.a)) && (left.d.$ === -1)) && (!left.d.a)) {
        var lK = left.b;
        var lV = left.c;
        var _v6 = left.d;
        var llK = _v6.b;
        var llV = _v6.c;
        var llLeft = _v6.d;
        var llRight = _v6.e;
        var lRight = left.e;
        return A5(
          $elm$core$Dict$RBNode_elm_builtin,
          0,
          lK,
          lV,
          A5($elm$core$Dict$RBNode_elm_builtin, 1, llK, llV, llLeft, llRight),
          A5($elm$core$Dict$RBNode_elm_builtin, 1, key, value, lRight, right));
      } else {
        return A5($elm$core$Dict$RBNode_elm_builtin, color, key, value, left, right);
      }
    }
  });
var $elm$core$Basics$compare = _Utils_compare;
var $elm$core$Dict$insertHelp = F3(
  function (key, value, dict) {
    if (dict.$ === -2) {
      return A5($elm$core$Dict$RBNode_elm_builtin, 0, key, value, $elm$core$Dict$RBEmpty_elm_builtin, $elm$core$Dict$RBEmpty_elm_builtin);
    } else {
      var nColor = dict.a;
      var nKey = dict.b;
      var nValue = dict.c;
      var nLeft = dict.d;
      var nRight = dict.e;
      var _v1 = A2($elm$core$Basics$compare, key, nKey);
      switch (_v1) {
        case 0:
          return A5(
            $elm$core$Dict$balance,
            nColor,
            nKey,
            nValue,
            A3($elm$core$Dict$insertHelp, key, value, nLeft),
            nRight);
        case 1:
          return A5($elm$core$Dict$RBNode_elm_builtin, nColor, nKey, value, nLeft, nRight);
        default:
          return A5(
            $elm$core$Dict$balance,
            nColor,
            nKey,
            nValue,
            nLeft,
            A3($elm$core$Dict$insertHelp, key, value, nRight));
      }
    }
  });
var $elm$core$Dict$insert = F3(
  function (key, value, dict) {
    var _v0 = A3($elm$core$Dict$insertHelp, key, value, dict);
    if ((_v0.$ === -1) && (!_v0.a)) {
      var k = _v0.b;
      var v = _v0.c;
      var l = _v0.d;
      var r = _v0.e;
      return A5($elm$core$Dict$RBNode_elm_builtin, 1, k, v, l, r);
    } else {
      return _v0;
    }
  });

module.exports = {
  empty: $elm$core$Dict$empty,
  insert: (key, value, dict) => A3($elm$core$Dict$insert, key, value, dict)
};

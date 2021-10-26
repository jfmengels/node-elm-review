// my-serializer-module
module.exports = {
  serialize(val, config, indentation, depth, refs, printer) {
    return val;
  },

  test(val) {
    return val && Array.isArray(val) && typeof val === 'object';
  },
};
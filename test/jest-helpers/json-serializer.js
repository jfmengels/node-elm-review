// my-serializer-module
module.exports = {
  serialize(val, config, indentation, depth, refs, printer) {
    return JSON.stringify(val, 0, 4);
  },

  test(val) {
    return val && Array.isArray(val) && typeof val === 'object';
  },
};
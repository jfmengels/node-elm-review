const PathHelpers = require('../lib/path-helpers');

test('should leave the path untouched if it does not contain odd characters', () => {
  const input = 'some-folder123';
  const output = PathHelpers.format(input);
  expect(output).toEqual(input);
});

test('should escape single quotes', () => {
  const input = "Don't-do-that";
  const output = PathHelpers.format(input);
  expect(output).toEqual("Don\\'t-do-that");
});

test('should escape double quotes', () => {
  const input = 'Don"t-do-that';
  const output = PathHelpers.format(input);
  expect(output).toEqual('Don\\"t-do-that');
});

test('should escape spaces', () => {
  const input = 'some path';
  const output = PathHelpers.format(input);
  expect(output).toEqual('some\\ path');
});

test('should escape *', () => {
  const input = 'some*path';
  const output = PathHelpers.format(input);
  expect(output).toEqual('some\\*path');
});

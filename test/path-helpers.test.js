const PathHelpers = require('../lib/path-helpers');

const desc = process.platform === 'win32' ? describe.skip : describe;

desc('format', () => {
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
});

describe('toUnixPath', () => {
  test('should convert Windows backslashes to forward slashes', () => {
    const input = 'src\\components\\Button.elm';
    const output = PathHelpers.toUnixPath(input);
    expect(output).toEqual('src/components/Button.elm');
  });

  test('should leave Unix paths unchanged', () => {
    const input = 'src/components/Button.elm';
    const output = PathHelpers.toUnixPath(input);
    expect(output).toEqual('src/components/Button.elm');
  });

  test('should handle mixed slashes', () => {
    const input = 'src\\components/Button.elm';
    const output = PathHelpers.toUnixPath(input);
    expect(output).toEqual('src/components/Button.elm');
  });

  test('should handle empty strings', () => {
    const input = '';
    const output = PathHelpers.toUnixPath(input);
    expect(output).toEqual('');
  });
});

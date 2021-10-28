const packageJson = require('../package.json');
const TestCli = require('./jest-helpers/cli');

test('Running with --version', async () => {
  const output = await TestCli.runWithoutTestMode('--version');
  expect(output.trimEnd()).toEqual(packageJson.version);
});

test('Running with the shorthand -v', async () => {
  const output = await TestCli.runWithoutTestMode('-v');
  expect(output.trimEnd()).toEqual(packageJson.version);
});

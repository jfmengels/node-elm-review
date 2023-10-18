const TestCli = require('./jest-helpers/cli');

function testName(name) {
  return `test/snapshots/help/${name}.txt`;
}

test('--help', async () => {
  const output = await TestCli.run('--help');
  expect(output).toMatchFile(testName('default'));
});

test('init --help', async () => {
  const output = await TestCli.run('init --help');
  expect(output).toMatchFile(testName('init'));
});

test('suppress --help', async () => {
  const output = await TestCli.run('suppress --help');
  expect(output).toMatchFile(testName('suppress'));
});

test('new-package --help', async () => {
  const output = await TestCli.run('new-package --help');
  expect(output).toMatchFile(testName('new-package'));
});

test('new-rule --help', async () => {
  const output = await TestCli.run('new-rule --help');
  expect(output).toMatchFile(testName('new-rule'));
});

test('prepare-offline --help', async () => {
  const output = await TestCli.run('prepare-offline --help');
  expect(output).toMatchFile(testName('prepare-offline'));
});

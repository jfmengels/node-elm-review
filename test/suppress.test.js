const path = require('path');
const childProcess = require('child_process');
const TestCli = require('./jest-helpers/cli');

function testName(name) {
  return `test/snapshots/suppress/${name}.txt`;
}

test('Running on project with only suppressed errors remaining should not exit with failure', () => {
  return TestCli.run('', {
    project: 'project-with-suppressed-errors'
  });
});

test('Running with --unsuppress should report suppressed errors', async () => {
  const output = await TestCli.runAndExpectError('--unsuppress', {
    project: 'project-with-suppressed-errors'
  });
  expect(output).toMatchFile(testName('suppressed-errors-unsuppress'));
});

test('Running with --unsuppress-rules should report suppressed errors for that rule', async () => {
  const output = await TestCli.runAndExpectError(
    '--unsuppress-rules NoUnused.Dependencies',
    {project: 'project-with-suppressed-errors'}
  );
  expect(output).toMatchFile(testName('suppressed-errors-unsuppress-rules'));
});

test('Running with "suppress --check-after-tests" when there are no uncommitted changes should not exit with failure', async () => {
  const output = await TestCli.run('suppress --check-after-tests', {
    project: 'project-with-suppressed-errors2'
  });
  expect(output).toEqual('');
});

test('Running with "suppress --check-after-tests" when there are uncommitted changes should exit with failure', async () => {
  const folder = path.resolve(
    __dirname,
    './project-with-suppressed-errors/review/suppressed/'
  );
  const filePath = folder + '/NoUnused.Variables.json';
  childProcess.execSync(`rm -r ${filePath}`);

  const output = await TestCli.runAndExpectError(
    'suppress --check-after-tests',
    {project: 'project-with-suppressed-errors'}
  );
  // Remove uncommitted suppression files
  childProcess.execSync(`git checkout HEAD ${folder}`);
  expect(output).toMatchFile(
    testName('suppressed-errors-check-with-uncommitted-changes')
  );
});

test('Running with unsupported version of suppression files should exit with failure', async () => {
  const output = await TestCli.runAndExpectError('', {
    project: 'project-with-unsupported-suppression-version'
  });
  expect(output).toMatchFile(testName('unsupported-suppression-version'));
});

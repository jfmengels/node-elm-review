const TestCli = require('./jest-helpers/cli');
const snapshotter = require('./snapshotter');

/**
 * @template {string} N
 * @param {N} name
 * @returns {`test/snapshots/suppress/${N}.txt`}
 */
function testName(name) {
  return snapshotter.snapshotPath('suppress', name);
}

test('Running with --unsuppress-rules should report suppressed errors for that rule', async () => {
  const {stdout, error} = await TestCli.internalRun(
    ['--unsuppress-rules', 'NoUnused.Dependencies'],
    'project-with-suppressed-errors'
  );
  expect(error).not.toBeUndefined();
  expect(stdout).toMatchFile(testName('suppressed-errors-unsuppress-rules'));
});

test('Running with "suppress --check-after-tests" when there are no uncommitted changes should not exit with failure', async () => {
  const {stdout, error} = await TestCli.internalRun(
    ['suppress', '--check-after-tests'],
    'project-with-suppressed-errors2'
  );
  expect(error).toBeUndefined();
  expect(stdout).toEqual('');
});

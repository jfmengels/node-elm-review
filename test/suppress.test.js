const path = require('pathe');
// @ts-expect-error(TS1479): zx doesn't ship CJS types.
const {$} = require('zx');
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

test('Running on project with only suppressed errors remaining should not exit with failure', async () => {
  return await TestCli.run([], {
    project: 'project-with-suppressed-errors'
  });
});

test('Running with --unsuppress should report suppressed errors', async () => {
  const output = await TestCli.runAndExpectError(['--unsuppress'], {
    project: 'project-with-suppressed-errors'
  });
  expect(output).toMatchFile(testName('suppressed-errors-unsuppress'));
});

test('Running with --unsuppress-rules should report suppressed errors for that rule', async () => {
  const output = await TestCli.runAndExpectError(
    ['--unsuppress-rules', 'NoUnused.Dependencies'],
    {project: 'project-with-suppressed-errors'}
  );
  expect(output).toMatchFile(testName('suppressed-errors-unsuppress-rules'));
});

test('Running with "suppress --check-after-tests" when there are no uncommitted changes should not exit with failure', async () => {
  const output = await TestCli.run(['suppress', '--check-after-tests'], {
    project: 'project-with-suppressed-errors2'
  });
  expect(output).toEqual('');
});

test('Running with "suppress --check-after-tests" when there are uncommitted changes should exit with failure', async () => {
  const folder = path.resolve(
    __dirname,
    './project-with-suppressed-errors/review/suppressed/'
  );
  const filePath = path.join(folder, 'NoUnused.Variables.json');
  await $`rm -r ${filePath}`;

  const output = await TestCli.runAndExpectError(
    ['suppress', '--check-after-tests'],
    {project: 'project-with-suppressed-errors'}
  );
  // Remove uncommitted suppression files
  await $({quiet: true})`git checkout HEAD ${folder}`;
  expect(output).toMatchFile(
    testName('suppressed-errors-check-with-uncommitted-changes')
  );
});

test('Running with unsupported version of suppression files should exit with failure', async () => {
  // In this setup, running `elm-review` should update a suppression file because
  // an unused variables issue has been fixed. It should however fail because
  // write permission has been removed from `review/suppressed/NoUnused.Variables.json`
  const project = 'project-with-suppressed-errors-no-write';
  const filePath = path.resolve(
    __dirname,
    project,
    'review/suppressed/NoUnused.Variables.json'
  );
  await $`chmod -w ${filePath}`;

  const output = await TestCli.runAndExpectError([], {project});
  expect(output).toMatchFile(testName('write-failure'));
});

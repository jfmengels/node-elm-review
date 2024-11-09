const TestCli = require('./jest-helpers/cli');
const snapshotter = require('./snapshotter');

/**
 * @template {string} N
 * @param {N} name
 * @returns {`test/snapshots/compiler-flag/${N}.txt`}
 */
function testName(name) {
  return snapshotter.snapshotPath('compiler-flag', name);
}

test('should retrieve `elm` binary from PATH', async () => {
  const output = await TestCli.run(
    '--config ../config-that-triggers-no-errors --force-build --compiler elm',
    {project: 'project-with-errors/'}
  );
  expect(output).toEqual('I found no errors!\n');
});

test('should retrieve `elm` binary locally when path is relative', async () => {
  const output = await TestCli.run(
    '--config ../config-that-triggers-no-errors --force-build --compiler ../../node_modules/.bin/elm',
    {project: 'project-with-errors/'}
  );
  expect(output).toEqual('I found no errors!\n');
});

test('should report an error when compiler could not be found', async () => {
  const output = await TestCli.runAndExpectError(
    '--config ../config-that-triggers-no-errors --force-build --compiler notfound',
    {project: 'project-using-es2015-module'}
  );
  expect(output).toMatchFile(testName('compiler-not-found'));
});

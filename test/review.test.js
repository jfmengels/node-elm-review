const path = require('path');
const childProcess = require('child_process');
const TestCli = require('./jest-helpers/cli');

function testName(name) {
  return `test/snapshots/review/${name}.txt`;
}

test('Regular run from inside the project', async () => {
  const output = await TestCli.runAndExpectError('', {
    project: 'project-with-errors/'
  });
  expect(output).toMatchFile('review-with-errors');
});

test('Regular run from inside the project (JSON output)', async () => {
  const output = await TestCli.runAndExpectError('', {
    project: 'project-with-errors/',
    report: 'json'
  });
  expect(output).toMatchFile(testName('review-with-errors-json'));
});

test('Regular run from inside the project (ndjson output)', async () => {
  const output = await TestCli.runAndExpectError('', {
    project: 'project-with-errors/',
    report: 'ndjson'
  });
  expect(output).toMatchFile(testName('review-with-errors-ndjson'));
});

test('Running using other configuration (without errors)', async () => {
  const output = await TestCli.run(
    '--config ../config-that-triggers-no-errors',
    {project: 'project-with-errors/'}
  );
  expect(output).toMatchFile(testName('no-errors'));
});

test('Regular run using --elmjson and --config', async () => {
  const output = await TestCli.runAndExpectError(
    '--elmjson project-with-errors/elm.json --config project-with-errors/review',
    {cwd: path.resolve(__dirname, '.')}
  );
  expect(output).toMatchFile(testName('run-with-elmjson-flag'));
});

test('Running in a project using ES2015 modules', async () => {
  const output = await TestCli.runAndExpectError('', {
    project: 'project-using-es2015-module'
  });
  expect(output).toMatchFile(testName('config-es2015-modules'));
});

test('Using an empty configuration', async () => {
  const output = await TestCli.runAndExpectError('--config ../config-empty', {
    project: 'project-with-errors'
  });
  expect(output).toMatchFile(testName('config-empty'));
});

test('Using a configuration with a missing direct elm-review dependency', async () => {
  const output = await TestCli.runAndExpectError(
    '--config ../config-without-elm-review',
    {project: 'project-with-errors'}
  );
  expect(output).toMatchFile(testName('without-elm-review'));
});

test('Using a configuration with an outdated elm-review package', async () => {
  const output = await TestCli.runAndExpectError(
    '--config ../config-for-outdated-elm-review-version',
    {project: 'project-with-errors'}
  );
  expect(output).toMatchFile(testName('outdated-version'));
});

test('Using a configuration which fails due to unknown module', async () => {
  const output = await TestCli.runAndExpectError(
    '--config ../config-error-unknown-module',
    {project: 'project-with-errors'}
  );
  expect(output).toMatchFile(testName('config-error-unknown-module'));
});

test('Using a configuration which fails due to syntax error', async () => {
  const output = await TestCli.runAndExpectError(
    '--config ../config-syntax-error',
    {project: 'project-with-errors'}
  );
  expect(output).toMatchFile(testName('config-syntax-error'));
});

test('Using a configuration which fails due to configuration error', async () => {
  const output = await TestCli.runAndExpectError(
    '--config ../config-configuration-error',
    {project: 'project-with-errors'}
  );
  expect(output).toMatchFile(testName('config-configuration-error'));
});

test('Using a configuration which fails due to debug remnants', async () => {
  const output = await TestCli.runAndExpectError(
    '--config ../config-error-debug',
    {project: 'project-with-errors'}
  );
  expect(output).toMatchFile(testName('config-error-debug'));
});

test('Running on project with unknown file', async () => {
  const output = await TestCli.runAndExpectError(
    '--config ../config-that-triggers-no-errors unknown-target',
    {project: 'project-with-errors'}
  );
  expect(output).toMatchFile(testName('run-with-unknown-target'));
});

test('Running on project with a directory ending in .elm (without arg)', async () => {
  const output = await TestCli.run(
    '--config ../config-that-triggers-no-errors',
    {project: 'project-with-dir-ending-in-elm'}
  );
  expect(output).toMatchFile(testName('src.elm-project-without-arg'));
});

test('Running on project with a directory ending in .elm (with arg)', async () => {
  const output = await TestCli.run(
    '--config ../config-that-triggers-no-errors src.elm',
    {project: 'project-with-dir-ending-in-elm'}
  );
  expect(output).toMatchFile(testName('src.elm-project-without-arg'));
});

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
    project: 'project-with-suppressed-errors'
  });
  expect(output).toEqual('');
});

test('Running with "suppress --check-after-tests" when there are uncommitted changes should exit with failure', async () => {
 childProcess.execSync(`rm -r ${path.resolve(__dirname, './project-with-suppressed-errors/review/suppressed/NoUnused.Variables.json')}`)

 const output = await TestCli.runAndExpectError(
   'suppress --check-after-tests',
   {project: 'project-with-suppressed-errors'}
 );
 // Remove uncommitted suppression files
 childProcess.execSync(`git checkout HEAD ${path.resolve(__dirname, './project-with-suppressed-errors/review/suppressed/')}`)
 expect(output).toMatchFile(testName('suppressed-errors-check-with-uncommitted-changes'));
});

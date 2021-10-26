const path = require('path');
const { toMatchFile } = require('jest-file-snapshot');
const TestCli = require('./jest-helpers/cli');

expect.extend({ toMatchFile });

test('Regular run from inside the project', async () => {
    const output = await TestCli.runAndExpectError(
        '',
        { project: "project-with-errors/" }
    );
    expect(output).toMatchSnapshot();
});

test('Regular run from inside the project (JSON output)', async () => {
    const output = await TestCli.runAndExpectError(
        '',
        { project: "project-with-errors/", report: 'json' }
    );
    expect(output).toMatchFile();
});

test('Regular run from inside the project (ndjson output)', async () => {
    const output = await TestCli.runAndExpectError(
        '',
        { project: "project-with-errors/", report: 'ndjson' }
    );
    expect(output).toMatchFile();
});

test('Running using other configuration (without errors)', async () => {
    const output = await TestCli.run(
        '--config ../config-that-triggers-no-errors',
        { project: "project-with-errors/" }
    );
    expect(output).toMatchSnapshot();
});

test("Regular run using --elmjson and --config", async () => {
    const output = await TestCli.runAndExpectError(
        "--elmjson project-with-errors/elm.json --config project-with-errors/review",
        { cwd: path.resolve(__dirname, ".") }
    );
    expect(output).toMatchSnapshot();
});

test("Running in a project using ES2015 modules", async () => {
    const output = await TestCli.runAndExpectError(
        "",
        { project: "project-using-es2015-module" }
    );
    expect(output).toMatchSnapshot();
});

test("Using an empty configuration", async () => {
    const output = await TestCli.runAndExpectError(
        "--config ../config-empty",
        { project: "project-with-errors" }
    );
    expect(output).toMatchSnapshot();
});

test("Using a configuration with a missing direct elm-review dependency", async () => {
    const output = await TestCli.runAndExpectError(
        "--config ../config-without-elm-review",
        { project: "project-with-errors" }
    );
    expect(output).toMatchSnapshot();
});

test("Using a configuration with an outdated elm-review package", async () => {
    const output = await TestCli.runAndExpectError(
        "--config ../config-for-outdated-elm-review-version",
        { project: "project-with-errors" }
    );
    expect(output).toMatchSnapshot();
});

test("Using a configuration which fails due to unknown module", async () => {
    const output = await TestCli.runAndExpectError(
        "--config ../config-error-unknown-module",
        { project: "project-with-errors" }
    );
    expect(output).toMatchSnapshot();
});

test("Using a configuration which fails due to syntax error", async () => {
    const output = await TestCli.runAndExpectError(
        "--config ../config-syntax-error",
        { project: "project-with-errors" }
    );
    expect(output).toMatchSnapshot();
});

test("Using a configuration which fails due to configuration error", async () => {
    const output = await TestCli.runAndExpectError(
        "--config ../config-configuration-error",
        { project: "project-with-errors" }
    );
    expect(output).toMatchSnapshot();
});

test("Using a configuration which fails due to debug remnants", async () => {
    const output = await TestCli.runAndExpectError(
        "--config ../config-error-debug",
        { project: "project-with-errors" }
    );
    expect(output).toMatchSnapshot();
});

test("Running on project with unknown file", async () => {
    const output = await TestCli.runAndExpectError(
        "--config ../config-that-triggers-no-errors unknown-target",
        { project: "project-with-errors" }
    );
    expect(output).toMatchSnapshot();
});

test("Running on project with a directory ending in .elm", async () => {
    const output = await TestCli.run(
        "--config ../config-that-triggers-no-errors",
        { project: "project-with-dir-ending-in-elm" }
    );
    expect(output).toMatchSnapshot();
});

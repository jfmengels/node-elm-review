const TestCli = require('./jest-helpers/cli');

test('Running with an unknown flag', async () => {
    const output = await TestCli.runAndExpectError('--watc');
    expect(output).toMatchSnapshot();
});

test('Running with an unknown shorthand flag', async () => {
    const output = await TestCli.runAndExpectError('-u');
    expect(output).toMatchSnapshot();
});

test("Running --compiler without an argument", async () => {
    const output = await TestCli.runAndExpectError("--compiler");
    expect(output).toMatchSnapshot();
});

test("Running --config without an argument", async () => {
    const output = await TestCli.runAndExpectError("--config");
    expect(output).toMatchSnapshot();
});

test("Running --template without an argument", async () => {
    const output = await TestCli.runAndExpectError("--template");
    expect(output).toMatchSnapshot();
});

test("Running --elmjson without an argument", async () => {
    const output = await TestCli.runAndExpectError("--elmjson");
    expect(output).toMatchSnapshot();
});

test("Running --report without an argument", async () => {
    const output = await TestCli.runAndExpectError("--report");
    expect(output).toMatchSnapshot();
});

test("Running --elm-format-path without an argument", async () => {
    const output = await TestCli.runAndExpectError("--elm-format-path");
    expect(output).toMatchSnapshot();
});

test("Running --rules without an argument", async () => {
    const output = await TestCli.runAndExpectError("--rules");
    expect(output).toMatchSnapshot();
});

test("Running --ignore-dirs without an argument", async () => {
    const output = await TestCli.runAndExpectError("--ignore-dirs");
    expect(output).toMatchSnapshot();
});

test("Running --ignore-files without an argument", async () => {
    const output = await TestCli.runAndExpectError("--ignore-files");
    expect(output).toMatchSnapshot();
});

test("Running init --compiler without an argument", async () => {
    const output = await TestCli.runAndExpectError("init --compiler");
    expect(output).toMatchSnapshot();
});

test("Running init --config without an argument", async () => {
    const output = await TestCli.runAndExpectError("init --config");
    expect(output).toMatchSnapshot();
});

test("Running init --template without an argument", async () => {
    const output = await TestCli.runAndExpectError("init --template");
    expect(output).toMatchSnapshot();
});

test("Running new-package --compiler without an argument", async () => {
    const output = await TestCli.runAndExpectError("new-package --compiler");
    expect(output).toMatchSnapshot();
});

test("Running --github-auth with a bad value", async () => {
    const output = await TestCli.runAndExpectError("--github-auth=bad");
    expect(output).toMatchSnapshot();
});

test("Running --report with an unknown value", async () => {
    const output = await TestCli.runAndExpectError("--report=unknown");
    expect(output).toMatchSnapshot();
});

test("Running --template with a bad value", async () => {
    const output = await TestCli.runAndExpectError("--template=not-github-repo");
    expect(output).toMatchSnapshot();
});

test("Running init --template with a bad value", async () => {
    const output = await TestCli.runAndExpectError("init --template=not-github-repo");
    expect(output).toMatchSnapshot();
});

test("Using the same flag twice", async () => {
    const output = await TestCli.runAndExpectError("--config a/ --config b/");
    expect(output).toMatchSnapshot();
});

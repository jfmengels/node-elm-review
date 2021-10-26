const TestCli = require('./jest-helpers/cli');

test('Running with an unknown flag', async () => {
    const output = await TestCli.runAndExpectError('--watc');
    expect(output).toMatchSnapshot();
});

test('Running with an unknown shorthand flag', async () => {
    const output = await TestCli.runAndExpectError('-u');
    expect(output).toMatchSnapshot();
});
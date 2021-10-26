const path = require('path');
const TestCli = require('./jest-helpers/cli');

test.only('Regular run from inside the project', async () => {
    const output = await TestCli.runAndExpectError(
        '',
        { cwd: path.resolve(__dirname, "project-with-errors/") }
    );
    expect(output).toMatchSnapshot();
})

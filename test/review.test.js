const path = require('path');
const TestCli = require('./jest-helpers/cli');

test('Regular run from inside the project', async () => {
    const output = await TestCli.runAndExpectError(
        '',
        { project: "project-with-errors/" }
    );
    expect(output).toMatchSnapshot();
});

test('Running using other configuration (without errors)', async () => {
    const output = await TestCli.run(
        '--config ../config-that-triggers-no-errors',
        { project: "project-with-errors/" }
    );
    expect(output).toMatchSnapshot();
});

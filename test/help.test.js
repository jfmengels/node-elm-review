const TestCli = require('./jest-helpers/cli');

test('--help', async () => {
    const output = await TestCli.run('--help');
    expect(output).toMatchSnapshot();
})

test('init --help', async () => {
    const output = await TestCli.run('init --help');
    expect(output).toMatchSnapshot();
})

test('suppress --help', async () => {
    const output = await TestCli.run('suppress --help');
    expect(output).toMatchSnapshot();
})

test('new-package --help', async () => {
    const output = await TestCli.run('new-package --help');
    expect(output).toMatchSnapshot();
})

test('new-rule --help', async () => {
    const output = await TestCli.run('new-rule --help');
    expect(output).toMatchSnapshot();
})

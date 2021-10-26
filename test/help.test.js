const { toMatchFile } = require('jest-file-snapshot');
const TestCli = require('./jest-helpers/cli');

expect.extend({ toMatchFile });

test('--help', async () => {
    const output = await TestCli.run('--help');
    expect(output).toMatchFile();
})

test('init --help', async () => {
    const output = await TestCli.run('init --help');
    expect(output).toMatchFile();
})

test('suppress --help', async () => {
    const output = await TestCli.run('suppress --help');
    expect(output).toMatchFile();
})

test('new-package --help', async () => {
    const output = await TestCli.run('new-package --help');
    expect(output).toMatchFile();
})

test('new-rule --help', async () => {
    const output = await TestCli.run('new-rule --help');
    expect(output).toMatchFile();
})

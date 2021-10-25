const path = require('path');
const spawnAsync = require('cross-spawn');
const util = require('util');
const exec = util.promisify(require('child_process').exec);
const version = require('../package.json').version;

test('--help', async () => {
    const output = await spawn('--help');
    expect(output.stdout).toMatchSnapshot();
})

test('init --help', async () => {
    const output = await spawn('init --help');
    expect(output.stdout).toMatchSnapshot();
})

test('suppress --help', async () => {
    const output = await spawn('suppress --help');
    expect(output.stdout).toMatchSnapshot();
})

test('new-package --help', async () => {
    const output = await spawn('new-package --help');
    expect(output.stdout).toMatchSnapshot();
})

test('new-rule --help', async () => {
    const output = await spawn('new-rule --help');
    expect(output.stdout).toMatchSnapshot();
})

const cli = path.resolve(__dirname, "../bin/elm-review");
function spawn(args) {
    return exec(`${cli} --FOR-TESTS ${args}`);
}
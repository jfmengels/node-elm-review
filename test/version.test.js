const path = require('path');
const util = require('util');
const exec = util.promisify(require('child_process').exec);
const packageJson = require('../package.json');

const cli = path.resolve(__dirname, "../bin/elm-review");

test('Running with --version', async () => {
    const result = await exec(`${cli} --version`);
    expect(result.stdout.trimEnd()).toEqual(packageJson.version);
});

test('Running with the shorthand -v', async () => {
    const result = await exec(`${cli} -v`);
    expect(result.stdout.trimEnd()).toEqual(packageJson.version);
});
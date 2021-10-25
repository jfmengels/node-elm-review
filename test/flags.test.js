const path = require('path');
const spawnAsync = require('cross-spawn');
const util = require('util');
const exec = util.promisify(require('child_process').exec);

test('Running with an unknown flag', async () => {
    return expect(spawn('--watc')
    .catch(err => {
        throw err.stdout;
    })
    ).rejects.toMatchSnapshot();
})

test('Running with an unknown shorthand flag', async () => {
    return expect(spawn('-u')
    .catch(err => {
        throw err.stdout;
    })
    ).rejects.toMatchSnapshot();
})

const cli = path.resolve(__dirname, "../bin/elm-review");
function spawn(args) {
    return exec(`${cli} ${args}`);
}
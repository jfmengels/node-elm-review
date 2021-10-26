const path = require('path');
const util = require('util');
const exec = util.promisify(require('child_process').exec);

const cli = path.resolve(__dirname, "../../bin/elm-review");

module.exports = {
    run,
    runWithoutTestMode
}

function run(args) {
    return internalExec(`--FOR-TESTS ${args}`);
}

function runWithoutTestMode(args) {
    return internalExec(args);
}

function internalExec(args) {
    return exec(`${cli} ${args}`)
        .then(result => result.stdout)
        .catch(err => {
            throw err.stdout;
        });
}
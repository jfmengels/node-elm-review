const path = require('path');
const util = require('util');
const exec = util.promisify(require('child_process').exec);

const cli = path.resolve(__dirname, "../../bin/elm-review");

module.exports = {
    run,
    runAndExpectError,
    runWithoutTestMode
}

function run(args) {
    return internalExec(`--FOR-TESTS ${args}`);
}

async function runAndExpectError(args) {
    try {
        const output = await internalExec(`--FOR-TESTS ${args}`);
        throw new Error(`CLI did not exit with an exit code as expected. Here is its output:\n\n${output}`);
    }
    catch(output) {
        return output;
    }
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
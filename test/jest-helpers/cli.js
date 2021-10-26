const path = require('path');
const util = require('util');
const exec = util.promisify(require('child_process').exec);

const cli = path.resolve(__dirname, "../../bin/elm-review");

module.exports = {
    run,
    runAndExpectError,
    runWithoutTestMode
}

function run(args, options) {
    return internalExec(`--FOR-TESTS ${args}`, options);
}

async function runAndExpectError(args, options) {
    try {
        const output = await internalExec(`--FOR-TESTS ${args}`, options);
        throw new Error(`CLI did not exit with an exit code as expected. Here is its output:\n\n${output}`);
    }
    catch(output) {
        return output;
    }
}

function runWithoutTestMode(args, options) {
    return internalExec(args, options);
}

function internalExec(args, options) {
    return exec(`${cli} ${args}`, options)
        .then(result => result.stdout)
        .catch(err => {
            throw err.stdout;
        });
}
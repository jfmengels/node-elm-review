const init = require('./init');

function help() {
  [
    init.description,
    '[--project path/to/project/to/lint/] # Lint the given project instead of the project of the current directory',
    '[--extra path/to/folder/to/lint/] # Additional folder to lint, like the tests folder or the lint folder. Repeat argument for several folders',
    '[--lint-folder path/to/your/lint/folder/] # Run linting with the configuration defined in the given folder',
    '[--compiler /path/to/compiler] # Run linting with given Elm compiler',
    '[--elm-format-path /path/to/elm-format] # Specify the path to `elm-format`, used when fixing errors automatically',
    '[--fix] # Automatically fix some of the errors, pending your approval',
    '[--version] # Print version string and exit',
    '[--debug] # Run in an non-optimized Elm program. This can allow you to have Debug statements in your configuration or rules',
    '[--no-color] # Disable coloring in the output'
  ].forEach(printUsage);
}

function printUsage(str) {
  console.log(`Usage: ${process.title} ${str}\n`);
}

module.exports = help;

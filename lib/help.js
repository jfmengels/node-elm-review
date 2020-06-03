const chalk = require('chalk');

function review(options) {
  /* eslint-disable prettier/prettier */
  console.log(`You are using ${chalk.greenBright(`elm-review ${options.packageJsonVersion}`)}.

    ${chalk.cyanBright('elm-review <zero-or-more-files-or-directories>')}
        Analyzes your project, and lists the locations where patterns forbidden
        by your configuration appear. It can potentially also fix some of the
        errors for you when adding ${chalk.blueBright('--fix')}.

        Unless files or directories are specified, ${chalk.greenBright('elm-review')} will look at:
        - For packages: src/ and tests/
        - For applications: the project’s elm.json’s "source-directories" and
          tests/

    ${chalk.yellowBright('elm-review init')}
        Creates an empty review configuration. It creates a ${chalk.yellowBright('review/elm.json')} and
        a ${chalk.cyan('review/src/ReviewConfig.elm')} file, and provides links to help you get
        started. Learn more by running ${chalk.yellowBright('elm-review init --help')}.

You can customize the review command with the following flags:

    ${chalk.cyan('--watch')}
        Re-run ${chalk.greenBright('elm-review')} automatically when your project changes.
        You can use ${chalk.cyan('--watch')} and ${chalk.blueBright('--fix')} together.

    ${chalk.cyan('--elmjson <path-to-elm.json>')}
        Specify the path to the elm.json file of the project. By default,
        the one in the current directory or its parent directories will be used.

    ${chalk.cyan('--config <path-to-review-directory>')}
        Use the review configuration in the specified directory instead of the
        one found in the current directory or one of its parents.

    ${chalk.cyan('--compiler <path-to-elm>')}
        Specify the path to the ${chalk.magentaBright('elm')} compiler.

    ${chalk.cyan('--version')}
        Print the version of the ${chalk.greenBright('elm-review')} CLI.

    ${chalk.cyan('--debug')}
        Add helpful information to debug your configuration or rules.
        - Print the list of reviewed files.
        - Run the compiler in debug mode, allowing you to use ${chalk.yellow('Debug')} statements
          in your configuration and custom rules.

If you wish to use ${chalk.blueBright('automatic fixing')}, you can use the following flags:

    ${chalk.blueBright('--fix')}
        ${chalk.greenBright('elm-review')} will present fixes for the errors that offer an automatic
        fix, which you can then accept or refuse one by one. When there are no
        more fixable errors left, ${chalk.greenBright('elm-review')} will report the remaining errors as
        if it was called without ${chalk.blueBright('--fix')}.
        Fixed files will be reformatted using ${chalk.magentaBright('elm-format')}.

    ${chalk.blueBright('--fix-all')}
        ${chalk.greenBright('elm-review')} will present a single fix containing the application of all
        available automatic fixes, which you can then accept or refuse.
        Afterwards, ${chalk.greenBright('elm-review')} will report the remaining errors as if it was
        called without ${chalk.blueBright('--fix-all')}.
        Fixed files will be reformatted using ${chalk.magentaBright('elm-format')}.

    ${chalk.cyan('--elm-format-path <path-to-elm-format>')}
        Specify the path to ${chalk.magentaBright('elm-format')}.
`);
  /* eslint-enable prettier/prettier */
}

function init() {
  /* eslint-disable prettier/prettier */
  console.log(`The init command helps getting started with ${chalk.greenBright('elm-review')}’s configuration.

    ${chalk.cyanBright('elm-review init')}
        It will ask permission to create several files:
        - ${chalk.yellowBright('review/elm.json')} in which you may add dependencies with review rules.
        - ${chalk.magentaBright('review/src/ReviewConfig.elm')} to define your configuration.

        After the files have been created, it will provide links to get you
        started.

You can customize the init command with the following flags:

    ${chalk.cyan('--config <path-to-review-directory>')}
        Create the configuration files in the specified directory instead of in
        the review/ directory.

    ${chalk.cyan('--compiler <path-to-elm>')}
        Specify the path to the ${chalk.magentaBright('elm')} compiler.
        The ${chalk.magentaBright('elm')} compiler is used to know the version of the compiler to write
        down in the ${chalk.yellowBright('review/elm.json')} file’s \`elm-version\` field. Use this if you
        have multiple versions of the ${chalk.magentaBright('elm')} compiler on your device.
`);
  /* eslint-enable prettier/prettier */
}

module.exports = {
  review,
  init
};

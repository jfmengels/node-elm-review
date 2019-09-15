const chalk = require('chalk');

function lint(packageJson) {
  /* eslint-disable prettier/prettier */
  console.log(`You are using ${chalk.greenBright(`elm-lint ${packageJson.version}`)}.

    ${chalk.cyanBright('elm-lint <zero-or-more-directories>')}
        Analyze your project, and lists the locations where patterns forbidden
        by your configuration appear. It can potentially also fix some of the
        errors for you when adding ${chalk.blueBright('--fix')}.

    ${chalk.yellowBright('elm-lint init')}
        Create an empty lint configuration. It creates a ${chalk.cyan('lint/elm.json')} and a
        ${chalk.cyan('lint/LintConfig.elm')} file, and provides links to help you get started.
        Learn more by running ${chalk.yellowBright('elm-lint init --help')}.

You can customize the linting command with the following flags:

    ${chalk.cyan('--project <path-to-project-to-lint>')}
        Analyze the project at the specified path, instead of the one in the
        current directory. The directory should contain an ${chalk.yellowBright('elm.json')} file.

    ${chalk.cyan('--config <path-to-lint-directory>')}
        Use the lint configuration in the specified directory instead of the one
        found in the current directory or above.

    ${chalk.cyan('--compiler <path-to-elm>')}
        Specify the path to the ${chalk.magentaBright('elm')} compiler.

    ${chalk.cyan('--version')}
        Print the version of the ${chalk.greenBright('elm-lint')} CLI.

    ${chalk.cyan('--debug')}
        Add helpful information to debug your configuration or rules.
        - Print the list of linted files.
        - Run the compiler in debug mode, allowing you to use ${chalk.yellow('Debug')} statements
          in your configuration and custom rules.

If you wish to use ${chalk.blueBright('automatic fixing')}, you can use the following flags:

    ${chalk.blueBright('--fix')}
        ${chalk.greenBright('elm-lint')} will present fixes for the errors that offer an automatic fix,
        which you can then accept or not. When there are no more fixable errors
        left, ${chalk.greenBright('elm-lint')} will report the remaining errors as if it was called
        without ${chalk.blueBright('--fix')}.
        Fixed errors will be reformatted using ${chalk.magentaBright('elm-format')}.

    ${chalk.cyan('--elm-format-path <path-to-elm-format>')}
        Specify the path to ${chalk.magentaBright('elm-format')}.
`);
  /* eslint-enable prettier/prettier */
}

function init() {
  /* eslint-disable prettier/prettier */
  console.log(`The init command helps getting started with ${chalk.greenBright('elm-lint')}'s configuration.

    ${chalk.cyanBright('elm-lint init')}
        It will ask permission to create several files:
        - ${chalk.yellowBright('lint/elm.json')} in which you may add dependencies with linting rules.
        - ${chalk.magentaBright('lint/LintConfig.elm')} in which you will define your configuration.

        After the files have been created, it will provide links to get you
        started.

You can customize the init command with the following flags:

    ${chalk.cyan('--config <path-to-lint-directory>')}
        Create the configuration files in the specified directory instead of in
        the lint/ directory.

    ${chalk.cyan('--compiler <path-to-elm>')}
        Specify the path to the ${chalk.magentaBright('elm')} compiler.
        The ${chalk.magentaBright('elm')} compiler is used to know the version of the compiler to write
        down in the ${chalk.yellowBright('lint/elm.json')} file's \`elm-version\` field. Use this if you
        have have multiple versions of the ${chalk.magentaBright('elm')} compiler on your device.
`);
  /* eslint-enable prettier/prettier */
}

module.exports = {
  lint,
  init
};

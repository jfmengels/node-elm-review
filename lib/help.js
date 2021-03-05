const chalk = require('chalk');
const Flags = require('./flags');
const Anonymize = require('./anonymize');

function review(options) {
  /* eslint-disable prettier/prettier */
  console.log(`You are using ${chalk.greenBright(`elm-review ${Anonymize.version(options)}`)}.

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

    ${chalk.yellowBright('elm-review new-package')}
        Creates an new project aimed to contain rules and to be published later.

    ${chalk.yellowBright('elm-review new-rule [RULE-NAME]')}
        Adds a new rule to your review configuration or review package.

You can customize the review command with the following flags:

${Flags.buildFlags(Flags.flags.filter(flag => flag.section === 'regular'))}

If you wish to use ${chalk.blueBright('automatic fixing')}, you can use the following flags:

${Flags.buildFlags(Flags.flags.filter(flag => flag.section === 'fix'))}
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

${Flags.buildFlags(Flags.flags.filter(flag => flag.section === 'init'))}

    ${chalk.cyan('--template <author>/<repo>[/path-to-the-config-folder][#branch-or-commit]')}
        Copy the review configuration from a GitHub repository, at the root or
        in a folder.
        Examples:
          - elm-review init --template author/elm-review-configuration
          - elm-review init --template jfmengels/elm-review-unused/example#master

    ${chalk.cyan('--compiler <path-to-elm>')}
        Specify the path to the ${chalk.magentaBright('elm')} compiler.
        The ${chalk.magentaBright('elm')} compiler is used to know the version of the compiler to write
        down in the ${chalk.yellowBright('review/elm.json')} file’s \`elm-version\` field. Use this if you
        have multiple versions of the ${chalk.magentaBright('elm')} compiler on your device.
`);
  /* eslint-enable prettier/prettier */
}

function newPackage() {
  /* eslint-disable prettier/prettier */
  console.log(`The new-package command scaffolds a new project to help you publish a package with ${chalk.greenBright('elm-review')} rules.

    ${chalk.cyanBright('elm-review new-package')}
        It will create a new project, containing:
        - An elm.json file
        - A src/ directory with an initial rule
        - A tests/ directory with an initial rule
        - A package.json with Elm tooling and scripts
        - A preconfigured review configuration, tailored for elm-review rules
        - A GitHub action to publish the package really easily

You can customize the new-package command with the following flags:

    ${chalk.cyan('--compiler <path-to-elm>')}
        Specify the path to the ${chalk.magentaBright('elm')} compiler.
        The ${chalk.magentaBright('elm')} compiler is used to know the version of the compiler to write
        down in the ${chalk.yellowBright('review/elm.json')} file’s \`elm-version\` field. Use this if you
        have multiple versions of the ${chalk.magentaBright('elm')} compiler on your device.
`);
  /* eslint-enable prettier/prettier */
}

function newRule() {
  console.log(`The new-rule command adds an empty rule to your review configuration or
review package.

    ${chalk.cyanBright('elm-review new-rule [RULE-NAME]')}
        It will add a rule file in src/ and a corresponding test file in tests/.
        If this is for a review package, the command will add the rule to the
        list of "exposed-modules" in the elm.json file. It will also add to the
        README.md a description of the rule and add the rule to the example
        configuration.
        If this is for a project with a review/ folder, you need to run this command
        from inside review/.

        RULE-NAME should be formatted just like an Elm module name, such as
        NoDoingThis or No.Doing.This. Read more about good names at
        https://package.elm-lang.org/packages/jfmengels/elm-review/latest/Review-Rule#a-good-rule-name

`);
}

module.exports = {
  review,
  init,
  newRule,
  newPackage
};

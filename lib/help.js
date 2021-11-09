const chalk = require('chalk');
const Flags = require('./flags');
const Anonymize = require('./anonymize');

function review(options) {
  const orange = chalk.keyword('orange');

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
        started. Learn more by running ${chalk.blueBright('elm-review init --help')}.

    ${chalk.yellowBright('elm-review suppress')}
        Generate suppression files for rules that report many errors. Use this
        when you wish to enable a rule without requiring fixing all the issues
        beforehand. Learn more by running ${orange('elm-review suppress --help')}.

    ${chalk.yellowBright('elm-review new-package')}
        Creates an new project aimed to contain rules and to be published later.

    ${chalk.yellowBright('elm-review new-rule [RULE-NAME]')}
        Adds a new rule to your review configuration or review package.

You can customize the review command with the following flags:

${Flags.buildFlags({section: 'regular', subcommand: null})}

If you wish to use ${chalk.blueBright('automatic fixing')}, you can use the following flags:

${Flags.buildFlags({section: 'fix', subcommand: null})}
`);
  /* eslint-enable prettier/prettier */
}

function suppress() {
  const orange = chalk.keyword('orange');

  /* eslint-disable prettier/prettier */
  console.log(`The suppress command helps adding new rules that report many errors
in your project.

    ${orange('elm-review suppress')}
        Reviews your project and generates suppression files for the reported
        errors.

${Flags.buildFlags({section: 'suppress-subcommand', subcommand: 'suppress'})}

${chalk.greenBright('elm-review')} has two systems to ignore reported errors.

First is the use of the ${chalk.cyan('Rule.ignoreErrorsForDirectories')} and
${chalk.cyan('Rule.ignoreErrorsForFiles')} functions in the ${chalk.cyan('ReviewConfig.elm')} file. These aim to
indicate the parts of the project where a rule would not provide value and
should be ignored, such as generated or vendored code.

The second system is the ${orange('temporarily suppressed')} errors system, which aims to
help you gradually adopt rules that report many errors in your project without
having you fix all the issues beforehand.

Running ${orange('elm-review suppress')} will generate a JSON file in ${orange('review/suppressed/')} for
every rule that currently reports errors, and records the number of suppressed
errors per file in your project.

While suppression files exist for your project, running ${chalk.greenBright('elm-review')} will behave
as usual but with these additional behaviors:
  - Suppressed errors won't be reported.
  - If there are outstanding errors for the ignored rules and files, the related
    suppressed errors will be reported until you reduce the number of errors
    back to the number in the JSON file. This is a good opportunity to fix more!
  - If no errors are being reported and there are less suppressed errors than
    before, suppression files will be updated automatically, in order to make
    sure no new errors get re-introduced unknowingly.

While you can run the ${orange('suppress')} command to ignore newly reported errors, please
do so with moderation. The aim of the suppression system is to allow enabling
rules while there are errors remaining and to have these fixed incrementally,
not to make it easier to ignore errors.

When you wish to tackle the suppressed errors, you can run ${chalk.greenBright('elm-review')} (without
the ${orange('suppress')} subcommand) with its available flags, and you can use the following
options to help you:

${Flags.buildFlags({section: 'suppress', subcommand: 'suppress'})}
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

${Flags.buildFlags({section: 'init', subcommand: 'init'})}
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

${Flags.buildFlags({section: 'new-package', subcommand: 'new-package'})}
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
  suppress,
  init,
  newRule,
  newPackage
};

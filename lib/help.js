/**
 * @import {Options} from './types/options';
 */
const chalk = require('chalk');
const Anonymize = require('./anonymize');
const Flags = require('./flags');

/**
 * @param {Options} options
 * @returns {void}
 */
function review(options) {
  const orange = chalk.keyword('orange');

  console.log(
    // prettier-ignore
    `You are using ${chalk.greenBright(`elm-review ${Anonymize.version(options)}`)}.

    ${chalk.magenta('elm-review <zero-or-more-files-or-directories>')}
        Analyzes your project, and lists the locations where patterns forbidden
        by your configuration appear. It can potentially also fix some of the
        errors for you when adding ${chalk.blueBright('--fix')}.

        Unless files or directories are specified, ${chalk.greenBright('elm-review')} will look at:
        - For packages: src/ and tests/
        - For applications: the project’s elm.json’s "source-directories" and
          tests/

    ${chalk.yellow('elm-review init')}
        Creates an empty review configuration. It creates a ${chalk.yellow('review/elm.json')} and
        a ${chalk.cyan('review/src/ReviewConfig.elm')} file, and provides links to help you get
        started. Learn more by running ${chalk.blueBright('elm-review init --help')}.

    ${chalk.yellow('elm-review suppress')}
        Generate suppression files for rules that report many errors. Use this
        when you wish to enable a rule without requiring fixing all the issues
        beforehand. Learn more by running ${orange('elm-review suppress --help')}.

    ${chalk.yellow('elm-review new-package')}
        Creates an new project aimed to contain rules and to be published later.

    ${chalk.yellow('elm-review new-rule [RULE-NAME]')}
        Adds a new rule to your review configuration or review package.

    ${chalk.yellow('elm-review prepare-offline')}
        Prepares running ${chalk.greenBright('elm-review')} in offline mode using ${chalk.cyan('--offline')}.

You can customize the review command with the following flags:

${Flags.buildFlags('regular', null)}

If you wish to use ${chalk.blueBright('automatic fixing')}, you can use the following flags:

${Flags.buildFlags('fix', null)}
`
  );
}

/**
 * @returns {void}
 */
function suppress() {
  const orange = chalk.keyword('orange');

  console.log(
    // prettier-ignore
    `The suppress command helps with fixing reported errors gradually.

This can be useful for instance when adding new rules that report many errors in
your project, instead of ignoring the rules on the files they currently report
errors for, or delaying enabling of the rule until all errors have been fixed.

    ${orange('elm-review suppress')}
        Reviews your project and generates suppression files for the reported
        errors. These files should be included in your versioning system.

${Flags.buildFlags('suppress-subcommand', 'suppress')}

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

When you wish to actively tackle the suppressed errors, you can run ${chalk.greenBright('elm-review')}
(without the ${orange('suppress')} subcommand) with its available flags, and you can use the
following additional flags to help you:

${Flags.buildFlags('suppress', 'suppress')}
`
  );
}

/**
 * @returns {void}
 */
function init() {
  console.log(
    // prettier-ignore
    `The init command helps getting started with ${chalk.greenBright('elm-review')}’s configuration.

    ${chalk.magenta('elm-review init')}
        It will ask permission to create several files:
        - ${chalk.yellow('review/elm.json')} in which you may add dependencies with review rules.
        - ${chalk.magentaBright('review/src/ReviewConfig.elm')} to define your configuration.

        After the files have been created, it will provide links to get you
        started.

You can customize the init command with the following flags:

${Flags.buildFlags('init', 'init')}
`
  );
}

/**
 * @returns {void}
 */
function newPackage() {
  console.log(
    // prettier-ignore
    `The new-package command scaffolds a new project to help you publish a package with ${chalk.greenBright('elm-review')} rules.

    ${chalk.magenta('elm-review new-package')}
        It will create a new project, containing:
        - An elm.json file
        - A src/ directory with an initial rule
        - A tests/ directory with an initial rule
        - A package.json with Elm tooling and scripts
        - A preconfigured review configuration, tailored for elm-review rules
        - A GitHub action to publish the package really easily

You can customize the new-package command with the following flags:

${Flags.buildFlags('new-package', 'new-package')}
`
  );
}

/**
 * @returns {void}
 */
function newRule() {
  console.log(`The new-rule command adds an empty rule to your review configuration or
review package.

    ${chalk.magenta('elm-review new-rule [RULE-NAME]')}
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

You can customize the new-rule command with the following flags:

${Flags.buildFlags('new-rule', 'new-rule')}
`);
}

/**
 * @returns {void}
 */
function prepareOffline() {
  console.log(`The prepare-offline command allows the tool to run in offline mode using
the ${chalk.cyan('--offline')} flag.

This will build the review configuration application and download the
dependencies of the project to review. It requires network access.

If you change your the review configuration, you might need to re-run this
command to work again in offline mode.

You can customize the new-rule command with the following flags:

${Flags.buildFlags('prepare-offline', 'prepare-offline')}
`);
}

module.exports = {
  review,
  suppress,
  init,
  newRule,
  newPackage,
  prepareOffline
};

const chalk = require('chalk');
const Anonymize = require('./anonymize');

const flags = {
  '*no subcommand*': [
    {
      public: true,
      boolean: false,
      name: 'compiler',
      whatItNeeds: 'the path to the Elm binary',
      argName: '<path-to-elm>',
      exampleArg: 'node_modules/.bin/elm',
      color: chalk.cyan,
      section: 'regular',
      description: [
        `Specify the path to the ${chalk.magentaBright('elm')} compiler.`
      ]
    },
    {
      public: true,
      boolean: false,
      name: 'config',
      whatItNeeds: 'the path to the review configuration directory',
      argName: '<path-to-review-directory>',
      exampleArg: 'review/',
      color: chalk.cyan,
      section: 'regular',
      description: [
        'Use the review configuration in the specified directory instead of the',
        'one found in the current directory or one of its parents.'
      ]
    },
    {
      public: true,
      boolean: false,
      name: 'rules',
      argName: '<rule1,rule2,...>',
      whatItNeeds: 'the list of rules to enable separated by commas',
      exampleArg: 'NoThis,NoThat',
      color: chalk.cyan,
      section: 'regular',
      description: [
        'Run with a subsection of the rules in the configuration. Specify them',
        'by their name, and separate them by commas.'
      ]
    }
  ]
};

function buildFlags(flagList) {
  return flagList
    .filter((flag) => flag.public)
    .map(buildFlag)
    .join('\n\n');
}

function buildFlag(flag) {
  return `    ${chalk.cyan(`--${flag.name} ${flag.argName}`)}
${flag.description.map((desc) => `        ${desc}`).join('\n')}`;
}

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

${buildFlags(flags['*no subcommand*'])}

    ${chalk.cyan('--rules <rule1,rule2,...>')}
        Run with a subsection of the rules in the configuration. Specify them
        by their name, and separate them by commas.

    ${chalk.cyan('--watch')}
        Re-run ${chalk.greenBright('elm-review')} automatically when your project changes.
        You can use ${chalk.cyan('--watch')} and ${chalk.blueBright('--fix')} together.

    ${chalk.cyan('--elmjson <path-to-elm.json>')}
        Specify the path to the elm.json file of the project. By default,
        the one in the current directory or its parent directories will be used.

    ${chalk.cyan('--config <path-to-review-directory>')}
        Use the review configuration in the specified directory instead of the
        one found in the current directory or one of its parents.

    ${chalk.cyan('--template <author>/<repo>[/path-to-the-config-folder][#branch-or-commit]')}
        Use the review configuration from a GitHub repository. You can use this
        to try out ${chalk.greenBright('elm-review')}, a configuration or a single rule.
        This flag requires Internet access, even after the first run.
        Examples:
          - elm-review --template author/elm-review-configuration
          - elm-review --template jfmengels/elm-review-unused/example#master

        I recommend to only use this temporarily, and run ${chalk.yellowBright('elm-review init')} with
        this same flag to copy the configuration to your project.

    ${chalk.cyan('--compiler <path-to-elm>')}
        Specify the path to the ${chalk.magentaBright('elm')} compiler.

    ${chalk.cyan('--version')}
        Print the version of the ${chalk.greenBright('elm-review')} CLI.

    ${chalk.cyan('--debug')}
        Add helpful information to debug your configuration or rules.
        - Print the list of reviewed files.
        - Run the compiler in debug mode, allowing you to use ${chalk.yellow('Debug')} statements
          in your configuration and custom rules.

    ${chalk.cyan('--report=json, --report=ndjson')}
        Error reports will be in JSON format. ${chalk.magenta('json')} prints a single JSON object
        while ${chalk.magenta('ndjson')} will print one JSON object per error each on a new line.
        The formats are described in this document: https://bit.ly/31F6jzz

    ${chalk.cyan('--no-details')}
        Hide the details from error reports for a more compact view.

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
  newPackage,
  flags
};

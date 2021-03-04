const chalk = require('chalk');

const flags = {
  '*no subcommand*': [
    {
      name: 'rules',
      public: true,
      boolean: false,
      argName: '<rule1,rule2,...>',
      whatItNeeds: 'the list of rules to enable separated by commas',
      exampleArg: 'NoThis,NoThat',
      usesEquals: false,
      color: chalk.cyan,
      section: 'regular',
      description: [
        'Run with a subsection of the rules in the configuration. Specify them',
        'by their name, and separate them by commas.'
      ]
    },
    {
      name: 'watch',
      public: true,
      boolean: true,
      color: chalk.cyan,
      section: 'regular',
      description: [
        /* eslint-disable prettier/prettier */
        `Re-run ${chalk.greenBright('elm-review')} automatically when your project changes.`,
        `You can use ${chalk.cyan('--watch')} and ${chalk.blueBright('--fix')} together.`
        /* eslint-enable prettier/prettier */
      ]
    },
    {
      name: 'elmjson',
      public: true,
      boolean: false,
      whatItNeeds: "the path to the project's elm.json",
      argName: '<path-to-elm.json>',
      exampleArg: 'elm.json',
      usesEquals: false,
      color: chalk.cyan,
      section: 'regular',
      description: [
        'Specify the path to the elm.json file of the project. By default,',
        'the one in the current directory or its parent directories will be used.'
      ]
    },
    {
      name: 'config',
      public: true,
      boolean: false,
      whatItNeeds: 'the path to the review configuration directory',
      argName: '<path-to-review-directory>',
      exampleArg: 'review/',
      usesEquals: false,
      color: chalk.cyan,
      section: 'regular',
      description: [
        'Use the review configuration in the specified directory instead of the',
        'one found in the current directory or one of its parents.'
      ]
    },
    {
      name: 'template',
      public: true,
      boolean: false,
      whatItNeeds: 'the GitHub repository',
      argName: '<author>/<repo>[/path-to-the-config-folder][#branch-or-commit]',
      exampleArg: 'jfmengels/elm-review-unused/example',
      usesEquals: false,
      color: chalk.cyan,
      section: 'regular',
      description: [
        /* eslint-disable prettier/prettier */
        'Use the review configuration from a GitHub repository. You can use this',
        `to try out ${chalk.greenBright('elm-review')}, a configuration or a single rule.`,
        'This flag requires Internet access, even after the first run.',
        'Examples:',
        '  - elm-review --template author/elm-review-configuration',
        '  - elm-review --template jfmengels/elm-review-unused/example#master',
        '',
        `I recommend to only use this temporarily, and run ${chalk.yellowBright('elm-review init')} with`,
        'this same flag to copy the configuration to your project.',
        /* eslint-enable prettier/prettier */
      ]
    },
    {
      name: 'compiler',
      public: true,
      boolean: false,
      whatItNeeds: 'the path to the Elm binary',
      argName: '<path-to-elm>',
      exampleArg: 'node_modules/.bin/elm',
      usesEquals: false,
      color: chalk.cyan,
      section: 'regular',
      description: [
        `Specify the path to the ${chalk.magentaBright('elm')} compiler.`
      ]
    },
    {
      name: 'version',
      public: true,
      boolean: true,
      color: chalk.cyan,
      section: 'regular',
      description: [
        /* eslint-disable prettier/prettier */
        `Print the version of the ${chalk.greenBright('elm-review')} CLI.`,
        /* eslint-enable prettier/prettier */
      ]
    },
    {
      name: 'debug',
      public: true,
      boolean: true,
      color: chalk.cyan,
      section: 'regular',
      description: [
        /* eslint-disable prettier/prettier */
        'Add helpful information to debug your configuration or rules.',
        '- Print the list of reviewed files.',
        `- Run the compiler in debug mode, allowing you to use ${chalk.yellow('Debug')} statements`,
        '  in your configuration and custom rules.',
        /* eslint-enable prettier/prettier */
      ]
    },
    {
      name: 'report',
      public: true,
      boolean: false,
      whatItNeeds: 'the report format',
      argName: '<json or ndjson>',
      exampleArg: 'json',
      usesEquals: true,
      color: chalk.cyan,
      section: 'regular',
      description: [
        /* eslint-disable prettier/prettier */
        `Error reports will be in JSON format. ${chalk.magenta('json')} prints a single JSON object`,
        `while ${chalk.magenta('ndjson')} will print one JSON object per error each on a new line.`,
        'The formats are described in this document: https://bit.ly/31F6jzz'
        /* eslint-enable prettier/prettier */
      ]
    },
    {
      name: 'no-details',
      public: true,
      boolean: true,
      color: chalk.cyan,
      section: 'regular',
      description: [
        'Hide the details from error reports for a more compact view.'
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
  const flagArgs = buildFlagsArgs(flag);
  return `    ${chalk.cyan(`--${flag.name}${flagArgs}`)}
${flag.description.map((desc) => `        ${desc}`).join('\n')}`;
}

function buildFlagsArgs(flag) {
  if (flag.boolean) {
    return '';
  }

  const delimiter = flag.usesEquals ? '=' : ' ';
  return delimiter + flag.argName;
}

module.exports = {
  flags,
  buildFlags,
  buildFlagsArgs
};

const chalk = require('chalk');

const flags = [
  {
    name: 'rules',
    boolean: false,
    argName: '<rule1,rule2,...>',
    mayBeUsedSeveralTimes: true,
    usesEquals: false,
    color: chalk.cyan,
    sections: ['regular'],
    description: [
      'Run with a subsection of the rules in the configuration. Specify them',
      'by their name, and separate them by commas.'
    ]
  },
  {
    name: 'watch',
    boolean: true,
    color: chalk.cyan,
    sections: ['regular'],
    description: [
      /* eslint-disable prettier/prettier */
      `Re-run ${chalk.greenBright('elm-review')} automatically when your project or configuration`,
      `changes. Use ${chalk.cyan('--watch-code')} to re-run only on project changes.`,
      `You can use ${chalk.cyan('--watch')} and ${chalk.blueBright('--fix')} together.`
      /* eslint-enable prettier/prettier */
    ]
  },
  {
    name: 'watch-code',
    boolean: true,
    color: chalk.cyan,
    sections: [],
    description: []
  },
  {
    name: 'elmjson',
    boolean: false,
    argName: '<path-to-elm.json>',
    mayBeUsedSeveralTimes: false,
    usesEquals: false,
    color: chalk.cyan,
    sections: ['regular'],
    description: [
      'Specify the path to the elm.json file of the project. By default,',
      'the one in the current directory or its parent directories will be used.'
    ]
  },
  {
    name: 'config',
    boolean: false,
    argName: '<path-to-review-directory>',
    mayBeUsedSeveralTimes: false,
    usesEquals: false,
    color: chalk.cyan,
    sections: ['regular', 'init'],
    description: [
      'Use the review configuration in the specified directory instead of the',
      'one found in the current directory or one of its parents.'
    ],
    initDescription: [
      'Create the configuration files in the specified directory instead of in',
      'the review/ directory.'
    ]
  },
  {
    name: 'template',
    boolean: false,
    argName: '<author>/<repo>[/path-to-the-config-folder][#branch-or-commit]',
    mayBeUsedSeveralTimes: false,
    usesEquals: false,
    color: chalk.cyan,
    sections: ['regular', 'init'],
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
    ],
    initDescription: [
      'Copy the review configuration from a GitHub repository, at the root or',
      'in a folder.',
      'Examples:',
      '  - elm-review init --template author/elm-review-configuration',
      '  - elm-review init --template jfmengels/elm-review-unused/example#master'
    ]
  },
  {
    name: 'compiler',
    boolean: false,
    argName: '<path-to-elm>',
    mayBeUsedSeveralTimes: false,
    usesEquals: false,
    color: chalk.cyan,
    sections: ['regular', 'init', 'new-package'],
    description: [
      `Specify the path to the ${chalk.magentaBright('elm')} compiler.`
    ],
    initDescription: [
      /* eslint-disable prettier/prettier */
      `Specify the path to the ${chalk.magentaBright('elm')} compiler.`,
      `The ${chalk.magentaBright('elm')} compiler is used to know the version of the compiler to write`,
      `down in the ${chalk.yellowBright('review/elm.json')} file’s \`elm-version\` field. Use this if you`,
      `have multiple versions of the ${chalk.magentaBright('elm')} compiler on your device.`
      /* eslint-enable prettier/prettier */
    ],
    newPackageDescription: [
      /* eslint-disable prettier/prettier */
      `Specify the path to the ${chalk.magentaBright('elm')} compiler.`,
      `The ${chalk.magentaBright('elm')} compiler is used to know the version of the compiler to write`,
      `down in the ${chalk.yellowBright('review/elm.json')} file’s \`elm-version\` field. Use this if you`,
      `have multiple versions of the ${chalk.magentaBright('elm')} compiler on your device.`
      /* eslint-enable prettier/prettier */
    ]
  },
  {
    name: 'version',
    alias: 'v',
    boolean: true,
    color: chalk.cyan,
    sections: ['regular'],
    description: [
      /* eslint-disable prettier/prettier */
        `Print the version of the ${chalk.greenBright('elm-review')} CLI.`,
        /* eslint-enable prettier/prettier */
    ]
  },
  {
    name: 'help',
    alias: 'h',
    boolean: true,
    color: chalk.cyan,
    sections: ['hidden'],
    description: []
  },
  {
    name: 'debug',
    boolean: true,
    color: chalk.cyan,
    sections: ['regular'],
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
    boolean: false,
    argName: '<json or ndjson>',
    mayBeUsedSeveralTimes: false,
    usesEquals: true,
    color: chalk.cyan,
    sections: ['regular'],
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
    boolean: true,
    color: chalk.cyan,
    sections: ['regular'],
    description: [
      'Hide the details from error reports for a more compact view.'
    ]
  },
  {
    name: 'details',
    boolean: true,
    sections: [],
    description: []
  },
  {
    name: 'fix',
    boolean: true,
    color: chalk.blueBright,
    sections: ['fix'],
    description: [
      /* eslint-disable prettier/prettier */
        `${chalk.greenBright('elm-review')} will present fixes for the errors that offer an automatic`,
        'fix, which you can then accept or refuse one by one. When there are no',
        `more fixable errors left, ${chalk.greenBright('elm-review')} will report the remaining errors as`,
        `if it was called without ${chalk.blueBright('--fix')}.`,
        `Fixed files will be reformatted using ${chalk.magentaBright('elm-format')}.`
        /* eslint-enable prettier/prettier */
    ]
  },
  {
    name: 'fix-all',
    boolean: true,
    color: chalk.blueBright,
    sections: ['fix'],
    description: [
      /* eslint-disable prettier/prettier */
        `${chalk.greenBright('elm-review')} will present a single fix containing the application of all`,
        'available automatic fixes, which you can then accept or refuse.',
        `Afterwards, ${chalk.greenBright('elm-review')} will report the remaining errors as if it was`,
        `called without ${chalk.blueBright('--fix-all')}.`,
        `Fixed files will be reformatted using ${chalk.magentaBright('elm-format')}.`
        /* eslint-enable prettier/prettier */
    ]
  },
  {
    name: 'fix-all-without-prompt',
    boolean: true,
    sections: [],
    description: []
  },
  {
    name: 'unsuppress',
    boolean: true,
    color: chalk.blueBright,
    sections: [],
    description: []
  },
  {
    name: 'elm-format-path',
    boolean: false,
    argName: '<path-to-elm-format>',
    mayBeUsedSeveralTimes: false,
    usesEquals: false,
    color: chalk.cyan,
    sections: ['fix'],
    description: [`Specify the path to ${chalk.magentaBright('elm-format')}.`]
  },
  {
    name: 'benchmark-info',
    boolean: true,
    sections: [],
    description: []
  },
  {
    name: 'ignore-problematic-dependencies',
    boolean: true,
    sections: [],
    description: []
  },
  {
    name: 'FOR-TESTS',
    boolean: true,
    sections: [],
    description: []
  },
  {
    name: 'force-build',
    boolean: true,
    sections: [],
    description: []
  },
  {
    name: 'no-color',
    boolean: true,
    sections: [],
    description: []
  },
  {
    name: 'github-auth',
    boolean: false,
    argName: '<github-api-token>',
    mayBeUsedSeveralTimes: false,
    usesEquals: true,
    color: chalk.cyan,
    sections: [],
    description: [
      `To be used along with ${chalk.cyan(
        '--template'
      )} to avoid GitHub rate limiting.`,
      'Follow https://docs.github.com/en/github/authenticating-to-github/creating-a-personal-access-token to create an API token. The API token needs access to public repositories.',
      '',
      'Then use the flag like this:',
      chalk.greenBright('  --github-auth=my-user-name:abcdef01234567890')
    ]
  },
  {
    name: 'namespace',
    boolean: false,
    argName: '<namespace>',
    mayBeUsedSeveralTimes: false,
    usesEquals: false,
    sections: [],
    description: []
  },
  {
    name: 'prefill',
    boolean: false,
    argName: '[author name[, package name[, license]]]',
    mayBeUsedSeveralTimes: false,
    usesEquals: false,
    sections: [],
    description: []
  },
  {
    name: 'ignore-dirs',
    boolean: false,
    argName: '<dir1,dir2,...>',
    mayBeUsedSeveralTimes: true,
    usesEquals: false,
    color: chalk.cyan,
    sections: ['regular'],
    description: [
      'Ignore the reports of all rules for the specified directories.'
    ]
  },
  {
    name: 'ignore-files',
    boolean: false,
    argName: '<file1,file2,...>',
    mayBeUsedSeveralTimes: true,
    usesEquals: false,
    color: chalk.cyan,
    sections: ['regular'],
    description: ['Ignore the reports of all rules for the specified files.']
  }
];

function buildFlags({section, subcommand}) {
  return flags
    .filter((flag) => flag.sections.includes(section))
    .map((flag) => buildFlag(subcommand, flag))
    .join('\n\n');
}

function buildFlag(subcommand, flag) {
  const flagArgs = buildFlagsArgs(flag);
  const preferredDescriptionField = preferredDescriptionFieldFor(subcommand);
  const description = flag[preferredDescriptionField] || flag.description;
  return `    ${flag.color(`--${flag.name}${flagArgs}`)}
${description.map((desc) => (desc ? `        ${desc}` : '')).join('\n')}`;
}

function preferredDescriptionFieldFor(subcommand) {
  switch (subcommand) {
    case 'init':
      return 'initDescription';
    case 'new-package':
      return 'newPackageDescription';
    default:
      return 'description';
  }
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
  buildFlag,
  buildFlags,
  buildFlagsArgs
};

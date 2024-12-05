/**
 * @import {Flag, Section} from './types/flag';
 * @import {Subcommand} from './types/options';
 */
const chalk = require('chalk');

const orange = chalk.keyword('orange');

/**
 * @type {Flag}
 */
const gitHubAuthFlag = {
  name: 'github-auth',
  boolean: false,
  argName: '<github-api-token>',
  mayBeUsedSeveralTimes: false,
  usesEquals: true,
  color: chalk.cyan,
  sections: [],
  description: [
    // prettier-ignore
    `To be used along with ${chalk.cyan('--template')} to avoid GitHub rate limiting.`,
    'Follow https://docs.github.com/en/github/authenticating-to-github/creating-a-personal-access-token to create an API token. The API token needs access to public repositories.',
    '',
    'Then use the flag like this:',
    chalk.greenBright('  --github-auth=github_pat_abcdef01234567890')
  ]
};

/**
 * @type {Flag}
 */
const reportFlag = {
  name: 'report',
  boolean: false,
  argName: '<json or ndjson>',
  mayBeUsedSeveralTimes: false,
  usesEquals: true,
  color: chalk.cyan,
  sections: ['regular'],
  description: [
    // prettier-ignore
    `Error reports will be in JSON format. ${chalk.magenta('json')} prints a single JSON object`,
    // prettier-ignore
    `while ${chalk.magenta('ndjson')} will print one JSON object per error each on a new line.`,
    'The formats are described in this document: https://bit.ly/31F6jzz'
  ]
};

/**
 * @type {Flag}
 */
const templateFlag = {
  name: 'template',
  boolean: false,
  argName: '<author>/<repo>[/path-to-the-config-folder][#branch-or-commit]',
  mayBeUsedSeveralTimes: false,
  usesEquals: false,
  color: chalk.cyan,
  sections: ['regular', 'init'],
  description: [
    'Use the review configuration from a GitHub repository. You can use this',
    // prettier-ignore
    `to try out ${chalk.greenBright('elm-review')}, a configuration or a single rule.`,
    'This flag requires Internet access, even after the first run.',
    'Examples:',
    '  - elm-review --template author/elm-review-configuration',
    '  - elm-review --template jfmengels/elm-review-unused/example#master',
    '',
    // prettier-ignore
    `I recommend to only use this temporarily, and run ${chalk.yellow('elm-review init')} with`,
    'this same flag to copy the configuration to your project.'
  ],
  initDescription: [
    'Copy the review configuration from a GitHub repository, at the root or',
    'in a folder. Examples:',
    '- elm-review init --template author/elm-review-configuration',
    '- elm-review init --template jfmengels/elm-review-config/package',
    '- elm-review init --template jfmengels/elm-review-config/application',
    '- elm-review init --template jfmengels/elm-review-unused/example#master'
  ]
};

/**
 * @type {Flag[]}
 */
const flags = [
  {
    name: 'unsuppress',
    boolean: true,
    color: chalk.cyan,
    sections: ['regular', 'suppress'],
    description: [
      // prettier-ignore
      `Include ${orange('suppressed')} errors in the error report for all rules.`
    ]
  },
  {
    name: 'unsuppress-rules',
    boolean: false,
    argName: '<rule1,rule2,...>',
    mayBeUsedSeveralTimes: true,
    usesEquals: false,
    color: chalk.cyan,
    sections: ['suppress'],
    description: [
      // prettier-ignore
      `Include ${orange('suppressed')} errors in the error report for the listed rules.`,
      'Specify the rules by their name, and separate them by commas.'
    ]
  },
  {
    name: 'rules',
    boolean: false,
    argName: '<rule1,rule2,...>',
    mayBeUsedSeveralTimes: true,
    usesEquals: false,
    color: chalk.cyan,
    sections: ['regular'],
    description: [
      'Run with a subsection of the rules in the configuration.',
      'Specify them by their name, and separate them by commas.'
    ]
  },
  {
    name: 'watch',
    boolean: true,
    color: chalk.cyan,
    sections: ['regular'],
    description: [
      // prettier-ignore
      `Re-run ${chalk.greenBright('elm-review')} automatically when your project or configuration`,
      // prettier-ignore
      `changes. Use ${chalk.cyan('--watch-code')} to re-run only on project changes.`,
      // prettier-ignore
      `You can use ${chalk.cyan('--watch')} and ${chalk.blueBright('--fix')} together.`
    ]
  },
  {
    name: 'watch-code',
    boolean: true,
    sections: null
  },
  {
    name: 'extract',
    boolean: true,
    color: chalk.cyan,
    sections: ['regular'],
    description: [
      'Enable extracting data from the project for the rules that have a',
      `data extractor. Requires running with ${chalk.cyan('--report=json')}.`,
      'Learn more by reading the section about "Extracting information"',
      'at https://bit.ly/3UmNr0V'
    ]
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
  templateFlag,
  {
    name: 'compiler',
    boolean: false,
    argName: '<path-to-elm>',
    mayBeUsedSeveralTimes: false,
    usesEquals: false,
    color: chalk.cyan,
    sections: ['regular', 'init', 'new-package', 'prepare-offline'],
    description: [
      `Specify the path to the ${chalk.magentaBright('elm')} compiler.`
    ],
    initDescription: [
      // prettier-ignore
      `Specify the path to the ${chalk.magentaBright('elm')} compiler.`,
      // prettier-ignore
      `The ${chalk.magentaBright('elm')} compiler is used to know the version of the compiler to write`,
      // prettier-ignore
      `down in the ${chalk.yellow('review/elm.json')} file’s \`elm-version\` field. Use this if you`,
      // prettier-ignore
      `have multiple versions of the ${chalk.magentaBright('elm')} compiler on your device.`
    ],
    newPackageDescription: [
      // prettier-ignore
      `Specify the path to the ${chalk.magentaBright('elm')} compiler.`,
      // prettier-ignore
      `The ${chalk.magentaBright('elm')} compiler is used to know the version of the compiler to write`,
      // prettier-ignore
      `down in the ${chalk.yellow('review/elm.json')} file’s \`elm-version\` field. Use this if you`,
      // prettier-ignore
      `have multiple versions of the ${chalk.magentaBright('elm')} compiler on your device.`
    ]
  },
  {
    name: 'rule-type',
    boolean: false,
    argName: '<module|project>',
    mayBeUsedSeveralTimes: false,
    usesEquals: false,
    color: chalk.cyan,
    sections: ['new-rule', 'new-package'],
    description: [
      `Whether the starting rule should be a module rule or a project rule.`,
      `Module rules are simpler but look at Elm modules in isolation, whereas`,
      `project rules are more complex but have access to information from the`,
      `entire project. You can always switch from a module rule to a project`,
      `rule manually later on.`
    ]
  },
  {
    name: 'version',
    alias: 'v',
    boolean: true,
    color: chalk.cyan,
    sections: ['regular'],
    description: [
      // prettier-ignore
      `Print the version of the ${chalk.greenBright('elm-review')} CLI.`
    ]
  },
  {
    name: 'help',
    alias: 'h',
    boolean: true,
    sections: null
  },
  {
    name: 'debug',
    boolean: true,
    color: chalk.cyan,
    sections: ['regular'],
    description: [
      'Add helpful pieces of information for debugging purposes.',
      // prettier-ignore
      `This will also run the compiler with ${chalk.cyan('--debug')}, allowing you to use`,
      // prettier-ignore
      `${chalk.yellow('Debug')} functions in your custom rules.`
    ]
  },
  {
    name: 'benchmark-info',
    boolean: true,
    color: chalk.cyan,
    sections: ['regular'],
    description: [
      'Print out how much time it took for rules and phases of the process to',
      'run. This is meant for benchmarking purposes.'
    ]
  },
  {
    name: 'color',
    boolean: true,
    sections: null
  },
  {
    name: 'no-color',
    boolean: true,
    color: chalk.cyan,
    sections: ['regular'],
    description: ['Disable colors in the output.']
  },
  reportFlag,
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
    sections: null
  },
  {
    name: 'fix',
    boolean: true,
    color: chalk.blueBright,
    sections: ['fix'],
    description: [
      // prettier-ignore
      `${chalk.greenBright('elm-review')} will present fixes for the errors that offer an automatic`,
      'fix, which you can then accept or refuse one by one. When there are no',
      // prettier-ignore
      `more fixable errors left, ${chalk.greenBright('elm-review')} will report the remaining errors as`,
      // prettier-ignore
      `if it was called without ${chalk.blueBright('--fix')}.`,
      // prettier-ignore
      `Fixed files will be reformatted using ${chalk.magentaBright('elm-format')}.`
    ]
  },
  {
    name: 'fix-all',
    boolean: true,
    color: chalk.blueBright,
    sections: ['fix'],
    description: [
      // prettier-ignore
      `${chalk.greenBright('elm-review')} will present a single fix containing the application of all`,
      'available automatic fixes, which you can then accept or refuse.',
      // prettier-ignore
      `Afterwards, ${chalk.greenBright('elm-review')} will report the remaining errors as if it was`,
      // prettier-ignore
      `called without ${chalk.blueBright('--fix-all')}.`,
      // prettier-ignore
      `Fixed files will be reformatted using ${chalk.magentaBright('elm-format')}.`
    ]
  },
  {
    name: 'fix-all-without-prompt',
    boolean: true,
    color: chalk.blueBright,
    sections: ['fix'],
    description: [
      // prettier-ignore
      `Same as ${chalk.blueBright('--fix-all')} but fixes are applied without a prompt.`,
      'I recommend committing all changes prior to running with this option and',
      'reviewing the applied changes afterwards.'
    ]
  },
  {
    name: 'fix-limit',
    boolean: false,
    argName: 'N',
    mayBeUsedSeveralTimes: false,
    usesEquals: true,
    color: chalk.blueBright,
    sections: ['fix'],
    description: ['Limit the number of fixes applied in a single batch to N.']
  },
  {
    name: 'allow-remove-files',
    boolean: true,
    color: chalk.blueBright,
    sections: ['fix'],
    description: ['Allow files to be removed by automatic fixes.']
  },
  {
    name: 'explain-fix-failure',
    boolean: true,
    color: chalk.blueBright,
    sections: ['fix'],
    description: ['Get more information about fixes that failed to apply.']
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
    sections: null
  },
  {
    name: 'ignore-problematic-dependencies',
    boolean: true,
    sections: null
  },
  {
    name: 'FOR-TESTS',
    boolean: true,
    sections: null
  },
  {
    name: 'force-build',
    boolean: true,
    sections: null
  },
  {
    name: 'offline',
    boolean: true,
    color: chalk.cyan,
    sections: ['regular'],
    description: [
      'Prevent making network calls. You might need to run',
      `${chalk.yellow(
        'elm-review prepare-offline'
      )} beforehand to avoid problems.`
    ]
  },
  gitHubAuthFlag,
  {
    name: 'namespace',
    boolean: false,
    argName: '<namespace>',
    mayBeUsedSeveralTimes: false,
    usesEquals: false,
    sections: null
  },
  {
    name: 'prefill',
    boolean: false,
    argName: '[author name[, package name[, license]]]',
    mayBeUsedSeveralTimes: false,
    usesEquals: false,
    sections: null
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
  },
  {
    name: 'check-after-tests',
    boolean: true,
    color: chalk.cyan,
    sections: ['suppress-subcommand'],
    description: [
      // prettier-ignore
      `Checks whether there are uncommitted suppression files. They may get`,
      // prettier-ignore
      `updated when running ${chalk.greenBright('elm-review')}, which people can forget to commit`,
      // prettier-ignore
      `before making a pull request. Running ${orange('elm-review suppress')} with this flag`,
      `at the end of your test suite makes sure these files stay up to date.`,
      `This command does not cause your project to be reviewed though.`
    ]
  }
];

/**
 * @param {Section} section
 * @param {Subcommand | null} subcommand
 * @returns {string}
 */
function buildFlags(section, subcommand) {
  /** @type {string[]} */
  const result = [];
  for (const flag of flags) {
    if (flag.sections === null) {
      continue;
    }

    if (flag.sections.includes(section)) {
      result.push(buildFlag(subcommand, flag));
    }
  }

  return result.join('\n\n');
}

/**
 * @param {Subcommand | null} subcommand
 * @param {Flag} flag
 * @returns {string}
 */
function buildFlag(subcommand, flag) {
  if (flag.sections === null) {
    return '';
  }

  const flagArgs = buildFlagsArgs(flag);
  const preferredDescriptionField = preferredDescriptionFieldFor(subcommand);
  const description = flag[preferredDescriptionField] ?? flag.description;
  return `    ${flag.color(`--${flag.name}${flagArgs}`)}
${description
  .map(
    /**
     * @param {string} desc
     * @returns {string}
     */
    (desc) => (desc ? `        ${desc}` : '')
  )
  .join('\n')}`;
}

/**
 * @param {Subcommand | null} subcommand
 * @returns {"initDescription" | "newPackageDescription" | "description"}
 */
function preferredDescriptionFieldFor(subcommand) {
  switch (subcommand) {
    case 'init': {
      return 'initDescription';
    }

    case 'new-package': {
      return 'newPackageDescription';
    }

    case 'new-rule': {
      return 'description';
    }

    case 'suppress': {
      return 'description';
    }

    case 'prepare-offline': {
      return 'description';
    }

    case null: {
      return 'description';
    }
  }
}

/**
 * @param {Flag} flag
 * @returns {string}
 */
function buildFlagsArgs(flag) {
  if (flag.boolean) {
    return '';
  }

  const delimiter = flag.usesEquals ? '=' : ' ';
  return delimiter + flag.argName;
}

module.exports = {
  flags,
  gitHubAuthFlag,
  reportFlag,
  templateFlag,
  buildFlag,
  buildFlags,
  buildFlagsArgs
};

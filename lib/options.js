// @flow
const path = require('path');
const chalk = require('chalk');
const findUp = require('find-up');
const minimist = require('minimist');
const levenshtein = require('fast-levenshtein');
const packageJson = require('../package.json');
const Flags = require('./flags');
const ErrorMessage = require('./error-message');

/*
These contain all the options that derive what and how elm-review will behave.

Some of these options are not documented in `--help`.
DO NOT DEPEND ON THEM!
They might get removed at any point.
Open an issue if you have a need for them, so that we can discuss what the best
course of action is and how to get forward.
 */

const availableSubcommands = ['init', 'new-package', 'new-rule', 'suppress'];

let containsHelp = false;

function compute(processArgv /* : Array<string> */) {
  containsHelp =
    processArgv.slice(2).includes('--help') ||
    processArgv.slice(2).includes('-h');

  const args = minimist(processArgv.slice(2), {
    alias: Flags.flags
      .filter((flag) => flag.alias)
      .reduce((object, flag) => {
        object[flag.name] = flag.alias;
        return object;
      }, {}),
    boolean: Flags.flags
      .filter((flag) => flag.boolean)
      .map((flag) => flag.name),
    default: {
      details: true
    },
    unknown: containsHelp ? () => true : unknownCheck()
  });

  const subcommand =
    availableSubcommands.find((subcmd) => subcmd === args._[0]) || null;
  const directoriesToAnalyze = subcommand === null ? args._ : args._.slice(1);

  if (!containsHelp) {
    checkForMissingArgs(subcommand, args);
    checkForInvalidArgs(subcommand, args);
  }

  const elmJsonPath = findElmJsonPath(args, subcommand);
  const readmePath =
    elmJsonPath && path.join(path.dirname(elmJsonPath), 'README.md');

  function initPath() {
    if (args.config) {
      return path.resolve(process.cwd(), args.config);
    }

    try {
      return path.join(projectToReview(), 'review');
    } catch {
      return path.join(process.cwd(), 'review');
    }
  }

  /* eslint-disable prettier/prettier */
  function projectToReview() {
    if (!elmJsonPath) {
      throw new ErrorMessage.CustomError(
'COULD NOT FIND ELM.JSON',
`I was expecting to find an ${chalk.yellowBright('elm.json')} file in the current directory or one of its parents, but I did not find one.

If you wish to run elm-review from outside your project,
try re-running it with ${chalk.cyan('--elmjson <path-to-elm.json>')}.`,
path.relative(process.cwd(), 'elm.json')
      );
    }

    return path.dirname(elmJsonPath);
  }
  /* eslint-enable prettier/prettier */

  const namespace = args.namespace || 'cli';

  function elmStuffFolder() {
    return path.join(
      projectToReview(),
      'elm-stuff',
      'generated-code',
      'jfmengels',
      'elm-review',
      namespace,
      packageJson.version
    );
  }

  function userSrc() {
    return args.config
      ? path.resolve(process.cwd(), args.config)
      : path.join(projectToReview(), 'review');
  }

  const template = args.template
    ? parseTemplate(subcommand, args.template)
    : null;

  const forTests = args['FOR-TESTS'];
  const {gitHubUser, gitHubPassword} = args['github-auth']
    ? parseGitHubAuth(subcommand, args['github-auth'])
    : {};

  const localElmReviewSrc = process.env.LOCAL_ELM_REVIEW_SRC;

  const [authorName, packageName, license] = args.prefill
    ? args.prefill.split(',')
    : [];
  const prefilledAnswers = {
    authorName,
    packageName,
    license
  };

  function listOfStrings(input) {
    if (typeof input === 'string') {
      return input.split(',');
    }

    if (Array.isArray(input)) {
      return input.reduce(
        (acc, subArray) => [...acc, ...subArray.split(',')],
        []
      );
    }

    return null;
  }

  return {
    debug: args.debug,
    showBenchmark: args['benchmark-info'],
    forTests,
    version: args.version,
    help: args.help,
    fix: args.fix,
    fixAll: args['fix-all'] || args['fix-all-without-prompt'],
    fixAllWithoutPrompt: args['fix-all-without-prompt'],
    detailsMode: args.details === false ? 'without-details' : 'with-details',
    watch: args.watch || args['watch-code'],
    watchConfig: args.watch,
    color: args.color,
    subcommand,
    namespace,
    compiler: args.compiler,
    elmFormatPath: args['elm-format-path'],
    packageJsonVersion: packageJson.version,
    localElmReviewSrc,
    forceBuild: args['force-build'],
    report: args.report === 'json' || args.report === 'ndjson' ? 'json' : null,
    reportOnOneLine: args.report === 'ndjson',
    rules: listOfStrings(args.rules),
    ignoredDirs: listOfStrings(args['ignore-dirs']) || [],
    ignoredFiles: listOfStrings(args['ignore-files']) || [],

    // TEMPORARY WORKAROUNDS
    ignoreProblematicDependencies: args['ignore-problematic-dependencies'],

    // NEW PACKAGE
    prefilledAnswers,

    // NEW RULE
    newRuleName: args._[1] || null,

    // PATHS - REVIEW APPLICATION

    userSrc,
    usedConfig: Boolean(args.config),
    template,
    initPath,
    elmModulePath: (appHash /* : string */) =>
      path.join(elmStuffFolder(), 'review-applications', `${appHash}.js`),
    elmParserPath: (elmSyntaxVersion /* : string */) =>
      path.resolve(
        process.cwd(),
        elmStuffFolder(),
        'elm-parser',
        `elm-syntax-v${elmSyntaxVersion}${args.debug ? '-debug' : ''}.js`
      ),
    generatedCodePackageJson: elmStuffFolder,
    templateElmModulePath: (commit /* : string */) => {
      if (!template) {
        // Should not happen, but makes Flow happy
        return 'MISSING-TEMPLATE';
      }

      return path.join(
        elmStuffFolder(),
        'review-applications',
        template.repoName,
        template.pathToFolder || '___root___',
        [
          commit,
          args.debug ? '-debug' : '',
          localElmReviewSrc ? '-local' : ''
        ].join('') + '.js'
      );
    },
    pathToTemplateElmJson: (commit /* : string */) => {
      if (!template) {
        // Should not happen, but makes Flow happy
        return 'MISSING-TEMPLATE';
      }

      return path.join(
        elmStuffFolder(),
        'remote-templates',
        template.repoName,
        template.pathToFolder || '___root___',
        commit,
        'elm.json'
      );
    },
    dependenciesCachePath: () =>
      path.join(elmStuffFolder(), 'dependencies-cache'),

    // PATHS - THINGS TO REVIEW
    elmJsonPath,
    elmJsonPathWasSpecified: Boolean(args.elmjson),
    readmePath,
    projectToReview,
    directoriesToAnalyze,
    fileCachePath: () => path.join(elmStuffFolder(), 'file-cache'),

    // GitHub tokens
    gitHubUser,
    gitHubPassword
  };
}

function parseTemplate(subcommand, string) {
  const match = /([^/]+\/[^#/]+)(\/[^#]+)?(#(.+))?/.exec(string);
  if (!match) {
    reportErrorAndExit(
      new ErrorMessage.CustomError(
        'INVALID FLAG ARGUMENT',
        `The value ${chalk.redBright(string)} passed to ${chalk.cyan(
          '--template'
        )} is not a valid one.

Here is the documentation for this flag:

${Flags.buildFlag(
  subcommand,
  Flags.flags.find((flag) => flag.name === 'template')
)}`
      )
    );
  }

  // $FlowFixMe
  const [, repoName, pathToFolder, , reference] = match;

  return {
    repoName,
    pathToFolder,
    reference
  };
}

function findElmJsonPath(args, subcommand) {
  if (args.elmjson) return args.elmjson;
  // Shortcutting the search for elm.json when `--help` since we won't need it
  if (args.help) return null;
  // Same when a subcommand is used, since we won't need it.
  if (subcommand && subcommand !== 'new-rule' && subcommand !== 'init')
    return null;
  return findUp.sync('elm.json');
}

function unknownCheck() {
  const allFlagNames = new Set(Flags.flags.map((flag) => flag.name));

  return (flag) => {
    const flagRegex = /^--(?<name>[^=]*)/;
    const match = flagRegex.exec(flag);
    if (containsHelp || !match) {
      return unknownShortHandFlagCheck(flag);
    }

    // $FlowFixMe
    const {name} = match.groups;
    if (!allFlagNames.has(name)) {
      reportErrorAndExit(
        new ErrorMessage.CustomError(
          'UNKNOWN FLAG',
          [
            'I did not recognize this flag:',
            '',
            `    ${chalk.redBright(name)}`,
            '',
            'Maybe you want one of these instead?',
            '',
            ...suggestions(name)
          ].join('\n')
        )
      );
    }

    return true;
  };
}

function unknownShortHandFlagCheck(flag) {
  const flagRegex = /^-(?<name>\w+)/;
  const match = flagRegex.exec(flag);

  if (!match) {
    return true;
  }

  // $FlowFixMe
  const flags = match.groups.name.split('');
  if (containsHelp || flags.includes('h')) {
    containsHelp = true;
    return true;
  }

  const aliases = Flags.flags.map((flag) => flag.alias).filter(Boolean);

  flags.forEach((flag) => {
    if (!aliases.includes(flag)) {
      reportErrorAndExit(
        new ErrorMessage.CustomError(
          'UNKNOWN FLAG',
          [
            `I did not recognize this shorthand flag: ${chalk.redBright(
              '-' + flag
            )}`,
            '',
            `I only know these: ${aliases
              .sort()
              .map((a) => chalk.greenBright('-' + a))
              .join(', ')}`
          ].join('\n')
        )
      );
    }
  });

  return true;
}

function suggestions(flag) {
  return Flags.flags
    .map((f) => ({
      ...f,
      distance: levenshtein.get(flag, f.name)
    }))
    .sort((a, b) => {
      if (a.distance < b.distance) {
        return -1;
      }

      if (a.distance > b.distance) {
        return 1;
      }

      return 0;
    })
    .slice(0, 2)
    .map((f) => chalk.greenBright(`    --${f.name}${Flags.buildFlagsArgs(f)}`));
}

function checkForMissingArgs(subcommand, args) {
  Flags.flags
    .filter((flag) => flag.boolean === false)
    .forEach((flag) => {
      if (typeof args[flag.name] === 'boolean') {
        reportErrorAndExit(
          new ErrorMessage.CustomError(
            'MISSING FLAG ARGUMENT',
            `The ${chalk.redBright(
              `--${flag.name}`
            )} flag needs more information.

Here is the documentation for this flag:

${Flags.buildFlag(subcommand, flag)}`
          )
        );
      }

      if (!flag.mayBeUsedSeveralTimes && Array.isArray(args[flag.name])) {
        reportErrorAndExit(
          new ErrorMessage.CustomError(
            'FLAG USED SEVERAL TIMES',
            `The ${chalk.redBright(
              `--${flag.name}`
            )} flag may not be used several times. I need a single value for this flag but I got several, and I don't know which one to choose.

In case it helps, here is the documentation for this flag:

${Flags.buildFlag(subcommand, flag)}`
          )
        );
      }
    });
}

function checkForInvalidArgs(subcommand, args) {
  if (args.report && !['json', 'ndjson', 'human'].includes(args.report)) {
    reportErrorAndExit(
      new ErrorMessage.CustomError(
        'INVALID FLAG ARGUMENT',
        `The value ${chalk.redBright(args.report)} passed to ${chalk.cyan(
          '--report'
        )} is not a valid one.

Here is the documentation for this flag:

${Flags.buildFlag(
  subcommand,
  Flags.flags.find((flag) => flag.name === 'report')
)}`
      )
    );
  }
}

function parseGitHubAuth(subcommand, gitHubAuth) {
  const split = gitHubAuth.split(':');
  if (split.length !== 2) {
    reportErrorAndExit(
      new ErrorMessage.CustomError(
        'INVALID FLAG ARGUMENT',
        `The value ${chalk.redBright(gitHubAuth)} passed to ${chalk.cyan(
          '--github-auth'
        )} is not a valid one.

Here is the documentation for this flag:

${Flags.buildFlag(
  subcommand,
  Flags.flags.find((flag) => flag.name === 'github-auth')
)}`
      )
    );
  }

  const [gitHubUser, gitHubPassword] = split;
  return {gitHubUser, gitHubPassword};
}

function reportErrorAndExit(errorToReport) {
  console.log(ErrorMessage.report({}, errorToReport));
  // eslint-disable-next-line unicorn/no-process-exit
  process.exit(1);
}

module.exports = {
  compute
};

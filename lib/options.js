const path = require('path');
const chalk = require('chalk');
// eslint-disable-next-line @typescript-eslint/ban-ts-comment
// @ts-ignore: wrap-ansi includes type definitions since version 8, but it also requires node 12
const wrap = require('wrap-ansi');
const findUp = require('find-up');
const minimist = require('minimist');
const levenshtein = require('fastest-levenshtein');
const packageJson = require('../package.json');
const Flags = require('./flags');
const ErrorMessage = require('./error-message');
const exit = require('../vendor/exit');

/**
 * @typedef { import("minimist").ParsedArgs } ParsedArgs
 * @typedef { import("./types/flag").Flag } Flag
 * @typedef { import("./types/path").Path } Path
 * @typedef { import("./types/options").Options } Options
 * @typedef { import("./types/options").Subcommand } Subcommand
 * @typedef { import("./types/options").Template } Template
 * @typedef { import("./types/content").ElmJsonData } ElmJsonData
 */

/*
These contain all the options that derive what and how elm-review will behave.

Some of these options are not documented in `--help`.
DO NOT DEPEND ON THEM!
They might get removed at any point.
Open an issue if you have a need for them, so that we can discuss what the best
course of action is and how to get forward.
 */

/**
 * @type {Subcommand[]}
 */
const availableSubcommands = [
  'init',
  'new-package',
  'new-rule',
  'suppress',
  'prepare-offline'
];

let containsHelp = false;

/**
 * Compute the options for this run.
 * @param {Array<string>} processArgv
 * @returns { Options }
 */
function compute(processArgv) {
  containsHelp =
    processArgv.slice(2).includes('--help') ||
    processArgv.slice(2).includes('-h');

  /** @type {ParsedArgs} */
  const args = minimist(processArgv.slice(2), {
    alias: Flags.flags
      .filter((flag) => flag.alias)
      .reduce((object, flag) => {
        // eslint-disable-next-line @typescript-eslint/ban-ts-comment
        // @ts-ignore - Handle this later
        object[flag.name] = flag.alias;
        return object;
      }, {}),
    boolean: Flags.flags
      .filter((flag) => flag.boolean)
      .map((flag) => flag.name),
    default: {
      color: true,
      details: true
    },
    unknown: containsHelp ? () => true : unknownCheck()
  });

  /** @type {Subcommand | null} */
  const subcommand =
    availableSubcommands.find((subcmd) => subcmd === args._[0]) || null;

  /** @type {Path[]} */
  const directoriesToAnalyze = subcommand === null ? args._ : args._.slice(1);

  if (!containsHelp) {
    checkForMissingArgs(subcommand, args);
    checkForInvalidArgs(subcommand, args);
  }

  /** @type {Path | null} */
  const elmJsonPath = findElmJsonPath(args, subcommand);
  /** @type {Path | null} */
  const readmePath =
    elmJsonPath && path.join(path.dirname(elmJsonPath), 'README.md');

  /**
   * @returns {Path}
   */
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

  function projectToReview() {
    if (!elmJsonPath) {
      throw new ErrorMessage.CustomError(
        'COULD NOT FIND ELM.JSON',
        // prettier-ignore
        `I was expecting to find an ${chalk.yellowBright('elm.json')} file in the current directory or one of its parents, but I did not find one.

If you wish to run elm-review from outside your project,
try re-running it with ${chalk.cyan('--elmjson <path-to-elm.json>')}.`,
        path.relative(process.cwd(), 'elm.json')
      );
    }

    return path.dirname(elmJsonPath);
  }

  function fixLimit() {
    const limit = args['fix-limit'];
    if (limit === undefined) {
      return undefined;
    }

    const n = Number.parseInt(limit, 10);
    if (Number.isNaN(n) || n < 1 || Math.floor(n) !== limit) {
      reportErrorAndExit(
        new ErrorMessage.CustomError(
          'INVALID FIX-LIMIT',
          // prettier-ignore
          `I was expecting a integer greater than 1 as the value for ${chalk.blueBright('--fix-limit=N')}, but got ${chalk.red(limit)}.`
        )
      );
    }

    return n;
  }

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

  function suppressedErrorsFolder() {
    return path.join(userSrc(), 'suppressed');
  }

  /**
   * @type { Template | null }
   */
  const template = args.template
    ? parseTemplate(subcommand, args.template)
    : null;

  const forTests = args['FOR-TESTS'];
  const {gitHubUser = undefined, gitHubPassword = undefined} = args[
    'github-auth'
  ]
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

  /**
   * Converts absolute to relative paths.
   *
   * @param {Path} filePath
   * @returns {Path}
   */
  function absolutePathsToRelative(filePath) {
    if (path.isAbsolute(filePath)) {
      return path.relative(projectToReview(), filePath);
    }

    return filePath;
  }

  return {
    debug: args.debug,
    showBenchmark: args['benchmark-info'],
    forTests,
    enableExtract: args.extract,
    version: args.version,
    help: args.help,
    fix: args.fix,
    fixLimit: fixLimit(),
    fixAll: args['fix-all'] || args['fix-all-without-prompt'],
    fixAllWithoutPrompt: args['fix-all-without-prompt'],
    unsuppress: parseUnsuppress(args),
    suppressCheckAfterTests: args['check-after-tests'],
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
    forceBuild: args['force-build'] || Boolean(localElmReviewSrc),
    offline: args.offline,
    report: args.report === 'json' || args.report === 'ndjson' ? 'json' : null,
    reportOnOneLine: args.report === 'ndjson',
    rulesFilter: listOfStrings(args.rules),
    ignoredDirs: () =>
      (listOfStrings(args['ignore-dirs']) || []).map(absolutePathsToRelative),
    ignoredFiles: () =>
      (listOfStrings(args['ignore-files']) || []).map(absolutePathsToRelative),

    // TEMPORARY WORKAROUNDS
    ignoreProblematicDependencies: args['ignore-problematic-dependencies'],

    // NEW PACKAGE
    prefilledAnswers,

    // NEW RULE
    newRuleName: args._[1] || null,
    ruleType: ['module', 'project'].includes(args['rule-type'])
      ? args['rule-type']
      : null,

    // PATHS - REVIEW APPLICATION

    userSrc,
    usedConfig: Boolean(args.config),
    template,
    initPath,
    suppressedErrorsFolder,
    buildFolder: () => path.join(elmStuffFolder(), 'build-project'),
    buildFolderForParserApp: () =>
      path.join(elmStuffFolder(), 'parser-app-build-project'),
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

    // PATHS - THINGS TO REVIEW
    elmJsonPath,
    elmJsonPathWasSpecified: Boolean(args.elmjson),
    readmePath,
    projectToReview,
    directoriesToAnalyze,
    fileCachePath: () => path.join(elmStuffFolder(), 'file-cache'),
    resultCachePath: (appHash /* : string */) =>
      path.join(elmStuffFolder(), 'result-cache', appHash),

    // GitHub tokens
    gitHubUser,
    gitHubPassword
  };
}

/**
 * @param {ParsedArgs} args
 * @returns {Array<string>|boolean}
 */
function parseUnsuppress(args) {
  if (args.unsuppress) {
    return true;
  }

  return listOfStrings(args['unsuppress-rules']) || false;
}

/**
 * @param {string | Array<string> | *} input
 * @returns {Array<string>|null}
 */
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

/**
 * @param {Subcommand | null} subcommand
 * @param {string} string
 * @returns {Template}
 */
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

${Flags.buildFlag(subcommand, Flags.templateFlag)}`
      )
    );
  }

  const [, repoName, pathToFolder, , reference] = match || [];

  return {
    repoName,
    pathToFolder,
    reference
  };
}

/**
 *
 * @param {ParsedArgs} args
 * @param {Subcommand | null} subcommand
 * @return {Path|null}
 */
function findElmJsonPath(args, subcommand) {
  if (args.elmjson) return args.elmjson;
  // Shortcutting the search for elm.json when `--help` since we won't need it
  if (args.help) return null;
  // Same when a subcommand is used, since we won't need it.
  if (
    subcommand &&
    subcommand !== 'new-rule' &&
    subcommand !== 'init' &&
    subcommand !== 'suppress' &&
    subcommand !== 'prepare-offline'
  ) {
    return null;
  }

  return findUp.sync('elm.json') || null;
}

/**
 * @returns {(flag: string) => boolean}
 */
function unknownCheck() {
  const allFlagNames = new Set(Flags.flags.map((flag) => flag.name));

  return (flag) => {
    const flagRegex = /^--(?<name>[^=]*)/;
    const match = flagRegex.exec(flag);
    if (containsHelp || !match || !match.groups) {
      return unknownShortHandFlagCheck(flag);
    }

    const {name} = match.groups;
    if (!allFlagNames.has(name)) {
      reportErrorAndExit(
        new ErrorMessage.CustomError('UNKNOWN FLAG', unknownFlagMessage(name))
      );
    }

    return true;
  };
}

/**
 * @param {string} name
 * @returns {string}
 */
function unknownFlagMessage(name) {
  if (name === 'suppress') {
    const orange = chalk.keyword('orange');
    return [
      'I did not recognize this flag:',
      '',
      `    ${chalk.redBright('--' + name)}`,
      '',
      `There is a ${orange(
        'suppress'
      )} subcommand available, did you mean that? Or do you want one of these instead?`,
      '',
      ...suggestions(name)
    ].join('\n');
  }

  return [
    'I did not recognize this flag:',
    '',
    `    ${chalk.redBright('--' + name)}`,
    '',
    'Maybe you want one of these instead?',
    '',
    ...suggestions(name)
  ].join('\n');
}

/**
 * @param {string} flag
 * @returns {boolean}
 */
function unknownShortHandFlagCheck(flag) {
  const flagRegex = /^-(?<name>\w+)/;
  const match = flagRegex.exec(flag);

  if (!match || !match.groups) {
    return true;
  }

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

/**
 * @param {string} flagName
 * @returns {Array<string>}
 */
function suggestions(flagName) {
  return Flags.flags
    .map((f) => ({
      ...f,
      distance: levenshtein.distance(flagName, f.name)
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

/**
 * @param {Subcommand | null} subcommand
 * @param {ParsedArgs} args
 * @returns {void}
 */
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

      if (
        !flag.boolean &&
        !flag.mayBeUsedSeveralTimes &&
        Array.isArray(args[flag.name])
      ) {
        reportErrorAndExit(
          new ErrorMessage.CustomError(
            'FLAG USED SEVERAL TIMES',
            // prettier-ignore
            `The ${chalk.redBright(`--${flag.name}`)} flag may not be used several times. I need a single value for this flag but I got several, and I don't know which one to choose.

In case it helps, here is the documentation for this flag:

${Flags.buildFlag(subcommand, flag)}`
          )
        );
      }
    });
}

/**
 * @param {Subcommand | null} subcommand
 * @param {ParsedArgs} args
 * @returns {void}
 */
function checkForInvalidArgs(subcommand, args) {
  if (args.report && !['json', 'ndjson', 'human'].includes(args.report)) {
    reportErrorAndExit(
      new ErrorMessage.CustomError(
        'INVALID FLAG ARGUMENT',
        `The value ${chalk.redBright(args.report)} passed to ${chalk.cyan(
          '--report'
        )} is not a valid one.

Here is the documentation for this flag:

${Flags.buildFlag(subcommand, Flags.reportFlag)}`
      )
    );
  }

  if (args.template && args.offline) {
    reportErrorAndExit(
      new ErrorMessage.CustomError(
        'COMMAND REQUIRES NETWORK ACCESS',
        wrap(
          `I can't use ${chalk.cyan('--template')} in ${chalk.cyan(
            'offline'
          )} mode, as I need network access to download the external template.

If you have the configuration locally on your computer, you can run it by pointing to it with ${chalk.yellow(
            '--config'
          )}.

Otherwise, I recommend you try to gain network access and initialize your configuration to be able to run it offline afterwards:

`,
          80
        ) + chalk.yellow('    elm-review init --template ' + args.template)
      )
    );
  }

  if (args.offline && subcommand === 'new-package') {
    reportErrorAndExit(
      new ErrorMessage.CustomError(
        'COMMAND REQUIRES NETWORK ACCESS',
        wrap(
          `I can't use ${chalk.yellow('new-package')} in ${chalk.cyan(
            'offline'
          )} mode, as I need network access to perform a number of steps.

I recommend you try to gain network access and try again.`,
          80
        )
      )
    );
  }
}

/**
 * @param {Subcommand | null} subcommand
 * @param {string} gitHubAuth
 * @return {{gitHubUser: string | undefined, gitHubPassword: string | undefined}}
 */
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

${Flags.buildFlag(subcommand, Flags.gitHubAuthFlag)}`
      )
    );
  }

  const [gitHubUser, gitHubPassword] = split;
  return {gitHubUser, gitHubPassword};
}

/** Report error and crash gracefully.
 *
 * @param {ErrorMessage.CustomError} errorToReport
 */
function reportErrorAndExit(errorToReport) {
  // @ts-expect-error - Handle this later
  console.log(ErrorMessage.report({}, errorToReport));

  exit(1);
}

module.exports = {
  compute
};

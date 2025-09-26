/**
 * This file contains all the options from which elm-review derives how it will behave.
 *
 * Some of these options are not documented in `--help`.
 * DO NOT DEPEND ON THEM!
 * They might get removed at any point.
 * They are not part of the user-facing public API and may be removed in a SemVer patch.
 * Open an issue if you have a need for them,
 * so that we can discuss what the best course of action is and how to move forward.
 */

/**
 * @import {ParsedArgs} from 'minimist';
 * @import {Path} from './types/path';
 * @import {Flag, Multi} from './types/flag';
 * @import {Options, Subcommand, Template} from './types/options';
 */
const path = require('node:path');
const chalk = require('chalk');
const levenshtein = require('fastest-levenshtein');
const findUp = require('find-up');
const minimist = require('minimist');
const wrap = require('wrap-ansi');
const packageJson = require('../package.json');
const exit = require('../vendor/exit');
const ErrorMessage = require('./error-message');
const Flags = require('./flags');

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
 *
 * @param {string[]} processArgv - An argument array (typically `process.argv`)
 * @param {Path} cwd - The current working directory (typically `process.cwd()`)
 * @returns {Options | never}
 */
function compute(processArgv, cwd) {
  containsHelp =
    processArgv.slice(2).includes('--help') ||
    processArgv.slice(2).includes('-h');

  const args = minimist(processArgv.slice(2), {
    alias: Flags.flags.reduce((object, flag) => {
      if (flag.alias !== undefined) {
        object[flag.name] = flag.alias;
      }

      return object;
    }, /** @type {Record<string, string>} */ ({})),
    boolean: Flags.flags.flatMap((flag) => (flag.boolean ? [flag.name] : [])),
    default: {
      color: true,
      details: true
    },
    unknown: containsHelp ? () => true : unknownCheck()
  });

  /** @type {Subcommand | null} */
  const subcommand =
    availableSubcommands.find((subcmd) => subcmd === args._[0]) ?? null;

  /** @type {Path[]} */
  const directoriesToAnalyze = subcommand === null ? args._ : args._.slice(1);

  if (!containsHelp) {
    checkForMissingArgs(subcommand, args);
    checkForInvalidArgs(subcommand, args);
  }

  /** @type {Path | null} */
  const elmJsonPath = findElmJsonPath(args, subcommand, cwd);
  /** @type {Path | null} */
  const readmePath =
    elmJsonPath && path.join(path.dirname(elmJsonPath), 'README.md');

  /**
   * @returns {Path}
   */
  function initPath() {
    if (args.config) {
      return path.resolve(cwd, args.config);
    }

    try {
      return path.join(projectToReview(), 'review');
    } catch {
      return path.join(cwd, 'review');
    }
  }

  /**
   * @returns {Path}
   */
  function projectToReview() {
    if (!elmJsonPath) {
      throw new ErrorMessage.CustomError(
        'COULD NOT FIND ELM.JSON',
        // prettier-ignore
        `I was expecting to find an ${chalk.yellowBright('elm.json')} file in the current directory or one of its parents, but I did not find one.

If you wish to run elm-review from outside your project,
try re-running it with ${chalk.cyan('--elmjson <path-to-elm.json>')}.`,
        path.relative(cwd, 'elm.json')
      );
    }

    return path.dirname(elmJsonPath);
  }

  /**
   * @returns {number | undefined | never}
   */
  function fixLimit() {
    const limit = args['fix-limit'];
    if (limit === undefined) {
      return;
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

  /**
   * @returns {Path}
   */
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

  /**
   * @returns {Path}
   */
  function userSrc() {
    return args.config
      ? path.resolve(cwd, args.config)
      : path.join(projectToReview(), 'review');
  }

  /** @returns {Path} */
  function suppressedErrorsFolder() {
    return path.join(userSrc(), 'suppressed');
  }

  /**
   * @type {Template | null}
   */
  const template = args.template
    ? parseTemplate(subcommand, args.template)
    : null;

  const forTests = args['FOR-TESTS'];

  const gitHubPat = parseGitHubAuth(subcommand, args['github-auth']);

  const localElmReviewSrc = process.env.LOCAL_ELM_REVIEW_SRC;

  /** @type {string} */
  const prefilled = args.prefill;
  const [authorName, packageName, license] = prefilled
    ? prefilled.split(',')
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
    fileRemovalFixesEnabled: args['allow-remove-files'],
    explainFixFailure: args['explain-fix-failure'],
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
      (listOfStrings(args['ignore-dirs']) ?? []).map(absolutePathsToRelative),
    ignoredFiles: () =>
      (listOfStrings(args['ignore-files']) ?? []).map(absolutePathsToRelative),

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
    cwd,
    userSrc,
    usedConfig: Boolean(args.config),
    template,
    initPath,
    suppressedErrorsFolder,
    buildFolder: () => path.join(elmStuffFolder(), 'build-project'),
    buildFolderForParserApp: () =>
      path.join(elmStuffFolder(), 'parser-app-build-project'),
    elmModulePath: (appHash) =>
      path.join(elmStuffFolder(), 'review-applications', `${appHash}.js`),
    elmParserPath: (elmSyntaxVersion) =>
      path.resolve(
        cwd,
        elmStuffFolder(),
        'elm-parser',
        `elm-syntax-v${elmSyntaxVersion}${args.debug ? '-debug' : ''}.js`
      ),
    generatedCodePackageJson: elmStuffFolder,
    templateElmModulePath: (commit) => {
      if (!template) {
        // Should not happen, but makes TS happy
        return 'MISSING-TEMPLATE';
      }

      return path.join(
        elmStuffFolder(),
        'review-applications',
        template.repoName,
        template.pathToFolder ?? '___root___',
        [
          commit,
          args.debug ? '-debug' : '',
          localElmReviewSrc ? '-local' : ''
        ].join('') + '.js'
      );
    },
    pathToTemplateElmJson: (commit) => {
      if (!template) {
        // Should not happen, but makes TS happy
        return 'MISSING-TEMPLATE';
      }

      return path.join(
        elmStuffFolder(),
        'remote-templates',
        template.repoName,
        template.pathToFolder ?? '___root___',
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
    resultCachePath: (appHash) =>
      path.join(elmStuffFolder(), 'result-cache', appHash),

    // GitHub token
    gitHubPat
  };
}

/**
 * @param {ParsedArgs} args
 * @returns {string[] | boolean}
 */
function parseUnsuppress(args) {
  if (args.unsuppress) {
    return true;
  }

  return listOfStrings(args['unsuppress-rules']) ?? false;
}

/**
 * @param {string | string[] | undefined} input
 * @returns {string[] | null}
 */
function listOfStrings(input) {
  if (typeof input === 'string') {
    return input.split(',');
  }

  if (Array.isArray(input)) {
    return input.reduce(
      (acc, subArray) => [...acc, ...subArray.split(',')],
      /** @type {string[]} */ ([])
    );
  }

  return null;
}

/**
 * @param {Subcommand | null} subcommand
 * @param {string} string
 * @returns {Template | never}
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

  const [, repoName, pathToFolder, , reference] = match ?? [];

  return {
    repoName,
    pathToFolder,
    reference
  };
}

/**
 * @param {ParsedArgs} args
 * @param {Subcommand | null} subcommand
 * @param {Path} cwd
 * @returns {Path | null}
 */
function findElmJsonPath(args, subcommand, cwd) {
  // eslint-disable-next-line @typescript-eslint/no-unsafe-return -- Casting is ugly.
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

  return findUp.sync('elm.json', {cwd}) ?? null;
}

/**
 * @returns {(flag: string) => true | never}
 */
function unknownCheck() {
  const allFlagNames = new Set(Flags.flags.map((flag) => flag.name));

  return (flag) => {
    const flagRegex = /^--(?<name>[^=]*)/;
    const match = flagRegex.exec(flag);
    if (containsHelp || !match?.groups) {
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
 * @returns {true | never}
 */
function unknownShortHandFlagCheck(flag) {
  const flagRegex = /^-(?<name>\w+)/;
  const match = flagRegex.exec(flag);

  if (!match?.groups) {
    return true;
  }

  const flags = [...match.groups.name];
  if (containsHelp || flags.includes('h')) {
    containsHelp = true;
    return true;
  }

  const aliases = Flags.flags.flatMap((flag) =>
    flag.alias === undefined ? [] : [flag.alias]
  );
  for (const flag of flags) {
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
  }

  return true;
}

/**
 * @param {string} flagName
 * @returns {string[]}
 */
function suggestions(flagName) {
  return Flags.flags
    .map((f) => ({
      ...f,
      distance: levenshtein.distance(flagName, f.name)
    }))
    .sort(
      /**
       * @param {Flag & {distance: number}} a
       * @param {Flag & {distance: number}} b
       * @returns {-1 | 0 | 1}
       */
      (a, b) => {
        if (a.distance < b.distance) {
          return -1;
        }

        if (a.distance > b.distance) {
          return 1;
        }

        return 0;
      }
    )
    .slice(0, 2)
    .map((f) => chalk.greenBright(`    --${f.name}${Flags.buildFlagsArgs(f)}`));
}

/**
 * @param {Subcommand | null} subcommand
 * @param {ParsedArgs} args
 * @returns {void | never}
 */
function checkForMissingArgs(subcommand, args) {
  for (const flag of Flags.flags.filter(
    /**
     * @param {Flag} flag
     * @returns {flag is Flag & Multi}
     */
    (flag) => flag.boolean === false
  )) {
    if (typeof args[flag.name] === 'boolean') {
      reportErrorAndExit(
        new ErrorMessage.CustomError(
          'MISSING FLAG ARGUMENT',
          `The ${chalk.redBright(`--${flag.name}`)} flag needs more information.

Here is the documentation for this flag:

${Flags.buildFlag(subcommand, flag)}`
        )
      );
    }

    if (!flag.mayBeUsedSeveralTimes && Array.isArray(args[flag.name])) {
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
  }
}

/**
 * @param {Subcommand | null} subcommand
 * @param {ParsedArgs} args
 * @returns {void | never}
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
        // @ts-expect-error(TS2349): `wrap-ansi` is funky.
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
        // @ts-expect-error(TS2349): `wrap-ansi` is funky.
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
 * @param {string | undefined} gitHubAuth
 * @returns {string | undefined | never}
 */
function parseGitHubAuth(subcommand, gitHubAuth) {
  if (gitHubAuth === undefined) return;

  const split = gitHubAuth.split(':');
  if (split.length !== 2 && split.length !== 1) {
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

  return split.length === 2 ? split[1] : split[0];
}

/**
 * Report error and crash gracefully.
 *
 * @param {ErrorMessage.CustomError} errorToReport
 * @returns {never}
 */
function reportErrorAndExit(errorToReport) {
  // @ts-expect-error(TS2345): Handle this later
  console.log(ErrorMessage.report({}, errorToReport));

  exit(1);
}

module.exports = {
  compute
};

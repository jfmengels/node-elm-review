const fs = require('fs');
const path = require('path');
const chalk = require('chalk');
const prompts = require('prompts');
const spawn = require('cross-spawn');
const getPathKey = require('path-key');
const FS = require('./fs-wrapper');
const AppState = require('./state');
const ErrorMessage = require('./error-message');
const promisifyPort = require('./promisify-port');
const StyledMessage = require('./styled-message');
const {startReview} = require('./run-review');
const ProjectDependencies = require('./project-dependencies');
const exit = require('../vendor/exit');

/**
 * @typedef { import("./types/options").Options } Options
 * @typedef { import("./types/app").App } App
 * @typedef { import("./types/app").AutofixRequest } AutofixRequest
 * @typedef { import("./types/state").FilesProposedByCurrentFix } FilesProposedByCurrentFix
 * @typedef { import("./types/path").Path } Path
 * @typedef { import("./types/content").File } File
 * @typedef { import("./types/elm-version").ElmVersion } ElmVersion
 */

module.exports = {
  subscribe
};

/**
 * Subscribe to fix requests to prompt the user.
 * @param {Options} options
 * @param {App} app
 * @param {ElmVersion} elmVersion
 */
function subscribe(options, app, elmVersion) {
  AppState.subscribe(
    app.ports.askConfirmationToFix,
    askConfirmationToFixWithOptions(options, app, elmVersion)
  );
}

/**
 * Subscribe to fix requests to prompt the user.
 * @param {Options} options
 * @param {App} app
 * @param {ElmVersion} elmVersion
 * @returns {(data: AutofixRequest) => Promise<void>}
 */
function askConfirmationToFixWithOptions(options, app, elmVersion) {
  return async (data) => {
    if (!options.fixAllWithoutPrompt) {
      StyledMessage.clearAndLog(
        options,
        data.confirmationMessage,
        data.clearFixLine
      );
    }

    const thereIsCurrentlyAFixProposalGoingOn =
      AppState.filesProposedByCurrentFix().length > 0;

    const shouldReReview = AppState.fixProposalReceived(data.changedFiles);
    if (shouldReReview) {
      return startReview(options, app);
    }

    const message =
      data.count === 1
        ? 'Do you wish to apply this fix?'
        : `Do you wish to apply the result of these ${data.count} fixes?`;

    if (thereIsCurrentlyAFixProposalGoingOn) {
      console.log(
        `${chalk.cyan('?')} ${chalk.bold(message)} ${chalk.gray('› (Y/n)')}`
      );
      return;
    }

    const accepted =
      options.fixAllWithoutPrompt ||
      (
        await prompts({
          type: 'confirm',
          name: 'accepted',
          message,
          initial: true
        })
      ).accepted;

    if (accepted === undefined) {
      // User interrupted the process using Ctrl-C

      exit(1);
    }

    /** @type {FilesProposedByCurrentFix} */
    const filesToFix = AppState.filesProposedByCurrentFix();
    if (
      filesToFix.length === 0 ||
      !(await checkIfAFixConfirmationIsStillExpected(app))
    ) {
      AppState.fixWasRefused();
      return;
    }

    if (accepted) {
      /** @type {File | undefined} */
      let modifiedElmJson;
      const basePath = options.projectToReview();

      const formattedFiles = Promise.all(
        filesToFix.map((file) => {
          const filePath = path.resolve(basePath, file.path);
          if (filePath.endsWith('.elm')) {
            // TODO Make this async
            return formatFileContent(options, file, filePath);
          }

          if (file.path === 'elm.json') {
            modifiedElmJson = file;
          }

          return FS.writeFile(filePath, file.source).then(() => file);
        })
      );

      let dependencies;
      if (modifiedElmJson) {
        // TODO Check if source-directories have changed, and if so, load/unload the necessary files.
        // TODO Check if dependencies have changed before we do this
        dependencies = await ProjectDependencies.collect(
          options,
          JSON.parse(modifiedElmJson.source),
          elmVersion
        );
      }

      AppState.fixWasAccepted();
      app.ports.userConfirmedFix.send({
        answer: true,
        files: await formattedFiles,
        dependencies
      });
    } else {
      AppState.fixWasRefused();
      app.ports.userConfirmedFix.send({
        answer: false
      });
    }
  };
}

function checkIfAFixConfirmationIsStillExpected(app) {
  return promisifyPort({
    subscribeTo: app.ports.fixConfirmationStatus,
    sendThrough: app.ports.askForFixConfirmationStatus,
    data: null
  });
}

/**
 * Format a file using elm-format
 * @param {Options} options
 * @param {File} file
 * @param {Path} filePath
 * @returns {File}
 */
function formatFileContent(options, file, filePath) {
  const hasElmFormatPathFlag = Boolean(options.elmFormatPath);
  const elmFormatPath = options.elmFormatPath || 'elm-format';

  const result = spawn.sync(
    elmFormatPath,
    ['--elm-version=0.19', '--stdin', '--output', filePath],
    {
      input: file.source,
      env: hasElmFormatPathFlag
        ? process.env
        : backwardsCompatibleElmFormatEnv()
    }
  );

  if (result.error) {
    if (result.error.code === 'ENOENT') {
      if (hasElmFormatPathFlag) {
        throw new ErrorMessage.CustomError(
          'ELM-FORMAT NOT FOUND',
          // prettier-ignore
          `I could not find the executable for ${chalk.magentaBright('elm-format')} at the location you specified:

  ${options.elmFormatPath}`,
          options.elmJsonPath
        );
      } else {
        throw new ErrorMessage.CustomError(
          'ELM-FORMAT NOT FOUND',
          // prettier-ignore
          `I could not find the executable for ${chalk.magentaBright('elm-format')}.

A few options:
- Install it globally
- Add it to your project through \`npm\`
- Specify the path using ${chalk.cyan('--elm-format-path <path-to-elm-format>')}`,
          options.elmJsonPath
        );
      }
    } else {
      throw result.error;
    }
  }

  if (result.status !== 0) {
    throw new ErrorMessage.CustomError(
      'ERROR WHEN RUNNING ELM-FORMAT',
      // prettier-ignore
      `I got an unexpected error when running ${chalk.magentaBright('elm-format')}:

${result.stderr.toString()}`,
      options.elmJsonPath
    );
  }

  return {
    // Need to return the file path as in memory of the Elm application,
    // as that is used as the id of the file.
    path: file.path,
    source: fs.readFileSync(filePath, 'utf8')
  };
}

// When `--elm-format-path` was _not_ provided, we used to execute
// `elm-format` like this:
//
// 1. Try `npx elm-format`
// 2. Try `elm-format`
//
// Just starting `npx` takes 200 ms though. Luckily `npx` isn’t even
// necessary, because the common ways of running `elm-review` are:
//
// 1. Install everything globally and run just `elm-review`.
// 2. Install everything locally and run `npx elm-review`.
// 3. Use the `--elm-format-path`.
//
// That’s also the only supported ways we have for the `elm` binary – there we
// have never tried to execute `npx elm`.
//
// `npx` adds all potential `node_modules/.bin` up to current directory to the
// beginning of PATH, for example:
//
//     ❯ npx node -p 'process.env.PATH.split(require("path").delimiter)'
//     [
//       '/Users/you/stuff/node_modules/.bin',
//       '/Users/you/node_modules/.bin',
//       '/Users/node_modules/.bin',
//       '/node_modules/.bin',
//       '/usr/bin',
//       'etc'
//     ]
//
// So if a user runs `npx elm-review`, when we later try to spawn just
// `elm-format`, it’ll be found since when spawning we inherit the same PATH.
//
// The `npx elm-format` approach has been removed to avoid those unnessary 200 ms,
// but to stay backwards compatible we prepend the same paths to the beginning
// of PATH just like `npx` would (see above). This is needed when:
//
// - Executing `elm-review` _without_ `npx`.
// - And expecting a _local_ `elm-format` to be used. That’s an odd use case,
//   but was supported due to the `npx` approach.
//
// This can be removed in a major version.
function backwardsCompatibleElmFormatEnv() {
  const pathKey = getPathKey();
  return {
    ...process.env,
    [pathKey]: [
      ...process
        .cwd()
        .split(path.sep)
        .map((_, index, parts) =>
          [...parts.slice(0, index + 1), 'node_modules', '.bin'].join(path.sep)
        )
        .reverse(),
      process.env[pathKey]
    ].join(path.delimiter)
  };
}

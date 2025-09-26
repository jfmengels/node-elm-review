/**
 * @import {ReviewApp, AutofixRequest} from './types/app';
 * @import {File} from './types/content';
 * @import {VersionString} from './types/version';
 * @import {Options} from './types/options';
 * @import {Path} from './types/path';
 * @import {Listened} from './types/promisify-port';
 * @import {FilesProposedByCurrentFix} from './types/state';
 */
const fs = require('node:fs');
const path = require('node:path');
const chalk = require('chalk');
const spawn = require('cross-spawn');
const prompts = require('prompts');
const exit = require('../vendor/exit');
const ErrorMessage = require('./error-message');
const FS = require('./fs-wrapper');
const {backwardsCompatiblePath, pathKey} = require('./npx');
const ProjectDependencies = require('./project-dependencies');
const promisifyPort = require('./promisify-port');
const {startReview} = require('./run-review');
const AppState = require('./state');
const StyledMessage = require('./styled-message');

/**
 * Subscribe to fix requests to prompt the user.
 *
 * @param {Options} options
 * @param {ReviewApp} app
 * @param {VersionString} elmVersion
 * @returns {void}
 */
function subscribe(options, app, elmVersion) {
  AppState.subscribe(
    app.ports.askConfirmationToFix,
    askConfirmationToFixWithOptions(options, app, elmVersion)
  );
}

/**
 * Subscribe to fix requests to prompt the user.
 *
 * @param {Options} options
 * @param {ReviewApp} app
 * @param {VersionString} elmVersion
 * @returns {Listened<AutofixRequest>}
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
      startReview(options, app);
      return;
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

    const accepted = options.fixAllWithoutPrompt || (await confirmFix(message));

    if (accepted === undefined) {
      // User interrupted the process using Ctrl-C

      exit(1);
    }

    /** @type {FilesProposedByCurrentFix} */
    const filesToFix = AppState.filesProposedByCurrentFix();
    if (
      (filesToFix.length === 0 && data.removedFiles.length === 0) ||
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
        filesToFix.map(async (file) => {
          const filePath = path.resolve(basePath, file.path);
          if (filePath.endsWith('.elm')) {
            // TODO(@jfmengels): Make this asynchronous.
            return formatFileContent(options, file, filePath);
          }

          if (file.path === 'elm.json') {
            modifiedElmJson = file;
          }

          await FS.writeFile(filePath, file.source);

          return file;
        })
      );

      let dependencies;
      if (modifiedElmJson) {
        // TODO(@jfmengels): Check if source-directories have changed, and if so, load/unload the necessary files.
        // TODO(@jfmengels): Check if dependencies have changed before we do this.
        dependencies = await ProjectDependencies.collect(
          options,
          JSON.parse(modifiedElmJson.source),
          elmVersion
        );
      }

      await Promise.all(
        data.removedFiles.map(async (filePath) => {
          await FS.remove(path.resolve(basePath, filePath));
        })
      );

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

/**
 * @param {string} message
 * @returns {Promise<boolean>}
 */
async function confirmFix(message) {
  /** @type {{accepted: boolean}} */
  const prompt = await prompts({
    type: 'confirm',
    name: 'accepted',
    message,
    initial: true
  });

  return prompt.accepted;
}

/**
 * @param {ReviewApp} app
 * @returns {PromiseLike<boolean>}
 */
function checkIfAFixConfirmationIsStillExpected(app) {
  return promisifyPort({
    subscribeTo: app.ports.fixConfirmationStatus,
    sendThrough: app.ports.askForFixConfirmationStatus,
    data: null
  });
}

/**
 * Format a file using elm-format
 *
 * @param {Options} options
 * @param {File} file
 * @param {Path} filePath
 * @returns {File}
 */
function formatFileContent(options, file, filePath) {
  const hasElmFormatPathFlag = Boolean(options.elmFormatPath);
  const elmFormatPath = options.elmFormatPath ?? 'elm-format';

  const result = spawn.sync(
    elmFormatPath,
    ['--elm-version=0.19', '--stdin', '--output', filePath],
    {
      input: file.source,
      env: {
        ...process.env,
        [pathKey]: backwardsCompatiblePath(options.elmFormatPath, options.cwd)
      }
    }
  );

  if (result.error) {
    if ('code' in result.error && result.error.code === 'ENOENT') {
      throw new ErrorMessage.CustomError(
        'ELM-FORMAT NOT FOUND',

        // prettier-ignore
        hasElmFormatPathFlag
          ? `I could not find the executable for ${chalk.magentaBright('elm-format')} at the location you specified:

  ${options.elmFormatPath}`
          : `I could not find the executable for ${chalk.magentaBright('elm-format')}.

A few options:
- Install it globally.
- Add it to your project through \`npm\`.
- Specify the path using ${chalk.cyan('--elm-format-path <path-to-elm-format>')}.`,
        options.elmJsonPath
      );
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

module.exports = {
  subscribe
};

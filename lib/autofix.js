const fs = require('fs-extra');
const chalk = require('chalk');
const prompts = require('prompts');
const spawn = require('cross-spawn');
const AppState = require('./state');
const errorMessage = require('./error-message');
const promisifyPort = require('./promisify-port');
const styledMessage = require('./styled-message');
const {startReview} = require('./run-review');

module.exports = {
  subscribe: (options, app) => {
    AppState.subscribe(
      app.ports.askConfirmationToFix,
      askConfirmationToFixWithOptions(options, app)
    );
  }
};

function askConfirmationToFixWithOptions(options, app) {
  return async (data) => {
    if (!options.fixAllWithoutPrompt) {
      styledMessage.clearAndLog(options, data.confirmationMessage);
    }

    const thereIsCurrentlyAFixProposalGoingOn =
      AppState.filesProposedByCurrentFix().length > 0;

    const shouldReReview = AppState.fixProposalReceived(data.changedFiles);
    if (shouldReReview) {
      return startReview(options, app);
    }

    if (thereIsCurrentlyAFixProposalGoingOn) {
      console.log(
        `${chalk.cyan('?')} ${chalk.bold(
          'Do you wish to apply this fix?'
        )} ${chalk.gray('› (Y/n)')}`
      );
      return;
    }

    const accepted =
      options.fixAllWithoutPrompt ||
      (
        await prompts({
          type: 'confirm',
          name: 'accepted',
          message: 'Do you wish to apply this fix?',
          initial: true
        })
      ).accepted;

    if (accepted === undefined) {
      // User interrupted the process using Ctrl-C
      // eslint-disable-next-line unicorn/no-process-exit
      process.exit(1);
    }

    const filesToFix = AppState.filesProposedByCurrentFix();
    if (
      filesToFix.length === 0 ||
      !(await checkIfAFixConfirmationIsStillExpected(app))
    ) {
      AppState.fixWasRefused();
      return;
    }

    if (accepted) {
      const formattedFiles = filesToFix.map((file) => {
        if (file.path.endsWith('.elm')) {
          return formatFileContent(options, file);
        }

        fs.writeFileSync(file.path, file.source);
        return file;
      });

      app.ports.userConfirmedFix.send({
        answer: true,
        files: formattedFiles
      });

      AppState.fixWasAccepted();
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

function formatFileContent(options, file) {
  if (options.elmFormatPath) {
    const spawnedUsingPathFromArgs = spawn.sync(
      options.elmFormatPath,
      ['--elm-version=0.19', '--stdin', '--output', file.path],
      {
        shell: true,
        input: file.source
      }
    );

    if (spawnedUsingPathFromArgs.status !== 0) {
      const error = spawnedUsingPathFromArgs.stderr.toString();
      if (error.includes('not found')) {
        throw new errorMessage.CustomError(
          /* eslint-disable prettier/prettier */
'ELM-FORMAT NOT FOUND',
`I could not find the executable for ${chalk.magentaBright('elm-format')} at the location you specified:
  ${options.elmFormatPath}`,
options.elmJsonPath
          /* eslint-enable prettier/prettier */
        );
      }
    }
  } else {
    const spawnedUsingNpx = spawn.sync(
      'npx',
      [
        '--no-install',
        'elm-format',
        '--elm-version=0.19',
        '--stdin',
        '--output',
        file.path
      ],
      {
        shell: true,
        input: file.source
      }
    );

    if (spawnedUsingNpx.status !== 0) {
      const error = spawnedUsingNpx.stderr.toString();
      if (error.includes('not found')) {
        throw new errorMessage.CustomError(
          /* eslint-disable prettier/prettier */
'ELM-FORMAT NOT FOUND',
`I could not find the executable for ${chalk.magentaBright('elm-format')}.

A few options:
- Install it globally
- Add it to your project through \`npm\`
- Specify the path using ${chalk.cyan('--elm-format-path <path-to-elm-format>')}`,
options.elmJsonPath
          /* eslint-enable prettier/prettier */
        );
      }

      const spawnedUsingGlobal = spawn.sync(
        'elm-format',
        ['--yes', '--elm-version=0.19', '--stdin', '--output', file.path],
        {
          shell: true,
          input: file.source
        }
      );

      if (spawnedUsingGlobal.status !== 0) {
        throw new errorMessage.CustomError(
          /* eslint-disable prettier/prettier */
'ERROR WHEN RUNNING ELM-FORMAT',
`I got an unexpected error when running ${chalk.magentaBright('elm-format')}:

  ${spawnedUsingGlobal.stderr.toString()}`,
options.elmJsonPath
            /* eslint-enable prettier/prettier */
        );
      }
    }
  }

  return {
    path: file.path,
    source: fs.readFileSync(file.path, 'utf8')
  };
}

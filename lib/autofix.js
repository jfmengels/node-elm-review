const fs = require('fs-extra');
const chalk = require('chalk');
const prompts = require('prompts');
const spawn = require('cross-spawn');
const appState = require('./state');
const errorMessage = require('./error-message');
const promisifyPort = require('./promisify-port');
const styledMessage = require('./styled-message');

module.exports = {
  subscribe: (options, app) => {
    appState.subscribe(
      app.ports.askConfirmationToFix,
      askConfirmationToFixWithOptions(options, app)
    );
  }
};

function askConfirmationToFixWithOptions(options, app) {
  return async (data) => {
    styledMessage.log(options, data.confirmationMessage);
    if (appState.filesProposedByCurrentFix().length > 0) {
      appState.fixProposalReceived(data.changedFiles);
      console.log(
        `${chalk.cyan('?')} ${chalk.bold(
          'Do you wish to apply this fix?'
        )} ${chalk.gray('› (Y/n)')}`
      );
      return;
    }

    appState.fixProposalReceived(data.changedFiles);

    const {accepted} = await prompts({
      type: 'confirm',
      name: 'accepted',
      message: 'Do you wish to apply this fix?',
      initial: true
    });

    if (accepted === undefined) {
      // User interrupted the process using Ctrl-C
      // eslint-disable-next-line unicorn/no-process-exit
      process.exit(1);
    }

    const filesToFix = appState.filesProposedByCurrentFix();
    if (
      filesToFix.length === 0 ||
      !(await checkIfAFixConfirmationIsStillExpected(app))
    ) {
      appState.fixWasRefused();
      return;
    }

    if (accepted) {
      // TODO Format file before saving it.
      // I could not manage to make this work at the moment
      //
      // const file = await formatFileContent(latestChangedFiles)
      // fs.writeFileSync(file)
      const formattedFiles = filesToFix.map((file) => {
        fs.writeFileSync(file.path, file.source);
        if (file.path.endsWith('.elm')) {
          return formatExistingFile(options, file);
        }

        return file;
      });

      app.ports.userConfirmedFix.send({
        answer: true,
        files: formattedFiles
      });

      appState.fixWasAccepted();
    } else {
      appState.fixWasRefused();
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

function formatExistingFile(options, file) {
  if (options.elmFormatPath) {
    const spawnedUsingPathFromArgs = spawn.sync(
      options.elmFormatPath,
      ['--yes', '--elm-version=0.19', file.path],
      {
        shell: true
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
      ['--no-install', 'elm-format', '--yes', '--elm-version=0.19', file.path],
      {shell: true}
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
        ['--yes', '--elm-version=0.19', file.path],
        {
          shell: true
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

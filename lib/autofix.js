const fs = require('fs-extra');
const chalk = require('chalk');
const prompts = require('prompts');
const spawn = require('cross-spawn');
const appState = require('./state');
const promisifyPort = require('./promisify-port');
const styledMessage = require('./styled-message');

let latestChangedFiles = null;

module.exports = {
  subscribe: (options, app) => {
    appState.subscribe(
      app.ports.askConfirmationToFix,
      askConfirmationToFixWithOptions(options, app)
    );
  }
};

function askConfirmationToFixWithOptions(options, app) {
  return async data => {
    styledMessage.log(options, data.confirmationMessage);
    if (latestChangedFiles) {
      latestChangedFiles = data.changedFiles;
      console.log(
        `${chalk.cyan('?')} ${chalk.bold(
          'Do you wish to apply this fix?'
        )} ${chalk.gray('› (Y/n)')}`
      );
      return;
    }

    latestChangedFiles = data.changedFiles;

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

    if (
      !latestChangedFiles ||
      !(await checkIfAFixConfirmationIsStillExpected(app))
    ) {
      latestChangedFiles = null;
      return;
    }

    if (accepted) {
      // TODO Format file before saving it.
      // I could not manage to make this work at the moment
      //
      // const file = await formatFileContent(latestChangedFiles)
      // fs.writeFileSync(file)
      const formattedFiles = latestChangedFiles.map(file => {
        fs.writeFileSync(file.path, file.source);
        if (file.path.endsWith('.elm')) {
          return formatExistingFile(options, file);
        }

        return null;
      });

      app.ports.userConfirmedFix.send({
        answer: true,
        files: latestChangedFiles
      });

      appState.filesWereUpdated(formattedFiles.filter(Boolean));
      latestChangedFiles = null;
    } else {
      latestChangedFiles = null;
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
      const errorMessage = spawnedUsingPathFromArgs.stderr.toString();
      if (errorMessage.includes('not found')) {
        throw new Error(
          `I could not find the executable for \`elm-format\` at: ${options.elmFormatPath}`
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
      if (!error.includes('not found')) {
        throw new Error(error);
      }

      const spawnedUsingGlobal = spawn.sync(
        'elm-format',
        ['--yes', '--elm-version=0.19', file.path],
        {
          shell: true
        }
      );
      if (spawnedUsingGlobal.status !== 0) {
        throw new Error(spawnedUsingGlobal.stderr.toString());
      }
    }
  }

  return {
    path: file.path,
    source: fs.readFileSync(file.path, 'utf8')
  };
}

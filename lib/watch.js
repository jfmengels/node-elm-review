const util = require('util');
const path = require('path');
const fs = require('fs-extra');
const chokidar = require('chokidar');
const Debug = require('./debug');
const Anonymize = require('./anonymize');
const AppState = require('./state');
const Runner = require('./runner');
const SuppressedErrors = require('./suppressed-errors');

const fsReadFile = util.promisify(fs.readFile);
const fsReadJson = util.promisify(fs.readJson);

let isFlushingStdio = false;

function watchFiles(
  options,
  {
    app,
    elmJsonData,
    elmFiles,
    sourceDirectories,
    reviewElmJson,
    reviewElmJsonPath
  },
  rebuildAndRewatch,
  onError
) {
  AppState.filesWereUpdated(elmFiles);

  let elmJsonContent = elmJsonData.project;

  let runReview = () => {
    Runner.requestReview(options, app);
  };

  if (!isFlushingStdio) {
    // This makes sure that any stdin input is removed before prompting the user.
    // That way, when the user presses Enter in watch mode when there is no report yet,
    // a proposed fix will not automatically be applied.
    process.stdin.on('readable', () => {
      // Use a loop to make sure we read all available data.
      while (process.stdin.read() !== null) {
        // Do nothing
      }
    });
    isFlushingStdio = true;
  }

  const elmJsonWatcher = chokidar
    .watch(removeWindowsSeparators(options.elmJsonPath), {ignoreInitial: true})
    .on('change', async () => {
      const newValue = await fsReadJson(options.elmJsonPath);
      if (JSON.stringify(newValue) !== JSON.stringify(elmJsonContent)) {
        elmJsonContent = newValue;
        runReview = () => {};
        clearTimeout(suppressedErrorsTimeout);
        await Promise.all([
          elmJsonWatcher.close(),
          readmeWatcher.close(),
          fileWatcher.close(),
          suppressedErrorsWatcher.close(),
          configurationWatcher && configurationWatcher.close()
        ]);

        if (options.report !== 'json') {
          if (!options.debug) {
            clearConsole();
          }

          Debug.log('Your `elm.json` has changed. Restarting elm-review.');
        }

        rebuildAndRewatch();

        // At the moment, since a lot of things can change (elm.json properties, source-directories, dependencies, ...),
        // it is simpler to re-run the whole process like when the configuration changes.
        //
        // We could try and handle each possible change separately to make this more efficient.
        //
        // app.ports.collectElmJson.send(newValue);
        // const projectDeps = await projectDependencies.collect(
        //   options,
        //   newValue,
        //   elmVersion
        // );
        // app.ports.collectDependencies.send(projectDeps);
        // runReview();
      }
    });

  const readmeWatcher = chokidar
    .watch(removeWindowsSeparators(options.readmePath), {ignoreInitial: true})
    .on('add', async () => {
      Debug.log('README.md has been added');

      const readme = {
        path: options.readmePath,
        content: await fsReadFile(options.readmePath, 'utf8')
      };

      AppState.readmeChanged(readme);
      app.ports.collectReadme.send(readme);
      runReview();
    })
    .on('change', async () => {
      const readme = {
        path: options.readmePath,
        content: await fsReadFile(options.readmePath, 'utf8')
      };
      const readmeHasChanged = AppState.readmeChanged(readme);
      if (readmeHasChanged) {
        Debug.log('README.md has been changed');

        app.ports.collectReadme.send(readme);
        runReview();
      }
    })
    .on('error', onError);

  const fileWatcher = chokidar
    .watch(
      sourceDirectories.map((directory) =>
        removeWindowsSeparators(`${directory}/**/*.elm`)
      ),
      {
        ignored: [
          'node_modules',
          'elm-stuff',
          '.*',
          '**/ElmjutsuDumMyM0DuL3.elm'
        ],
        ignoreInitial: true
      }
    )
    .on('add', async (absolutePath) => {
      const relativePath = path.relative(process.cwd(), absolutePath);

      Debug.log(`File ${Anonymize.path(options, relativePath)} has been added`);

      let elmFile = AppState.getFileFromMemoryCache(relativePath);

      const isNewFile = !elmFile;

      if (!elmFile) {
        elmFile = {
          path: relativePath,
          source: '',
          ast: null
        };
      }

      const newSource = await fsReadFile(relativePath, 'utf8');

      if (elmFile.source !== newSource) {
        // NOTE: Mutates the file cache
        elmFile.source = newSource;
        elmFile.ast = null;
      }

      if (isNewFile) {
        AppState.filesWereUpdated([elmFile]);
      }

      app.ports.collectFile.send(elmFile);
      runReview();
    })
    .on('change', async (absolutePath) => {
      const relativePath = path.relative(process.cwd(), absolutePath);

      let elmFile = AppState.getFileFromMemoryCache(relativePath);
      if (!elmFile) {
        elmFile = {
          path: relativePath,
          source: '',
          ast: null
        };
      }

      const newSource = await fsReadFile(relativePath, 'utf8');

      if (elmFile.source !== newSource) {
        Debug.log(
          `File ${Anonymize.path(options, relativePath)} has been changed`
        );

        // NOTE: Mutates the file cache
        elmFile.source = newSource;
        elmFile.ast = null;
        app.ports.collectFile.send(elmFile);
        runReview();
      }
    })
    .on('unlink', (absolutePath) => {
      const relativePath = path.relative(process.cwd(), absolutePath);
      Debug.log(
        `File ${Anonymize.path(options, relativePath)} has been removed`
      );

      app.ports.removeFile.send(relativePath);
      runReview();
    })
    .on('error', onError);

  let suppressedErrorsTimeout = null;
  function updateSuppressedErrors() {
    // TODO Write last save time for each of these in appstate, and compare with the last update time
    // that is given as argument to this function. If possible, don't do anything.
    clearTimeout(suppressedErrorsTimeout);
    suppressedErrorsTimeout = setTimeout(async () => {
      const suppressedErrors = await SuppressedErrors.read(options);
      // TODO Avoid doing anything if suppressed errors haven't changed
      //    It's likely this program's fault for changing anything anyway
      Debug.log('Suppressed errors have been added');
      app.ports.updateSuppressedErrors.send(suppressedErrors);
    }, 20);
  }

  const suppressedErrorsWatcher = chokidar
    .watch(
      removeWindowsSeparators(`${options.suppressedErrorsFolder()}/*.json`),
      {ignoreInitial: true}
    )
    .on('add', updateSuppressedErrors)
    .on('change', updateSuppressedErrors)
    .on('unlink', updateSuppressedErrors)
    .on('error', onError);

  const configurationWatcher = watchConfiguration(
    options,
    {reviewElmJson, reviewElmJsonPath},
    async () => {
      runReview = () => {};

      clearTimeout(suppressedErrorsTimeout);
      await Promise.all([
        elmJsonWatcher.close(),
        readmeWatcher.close(),
        fileWatcher.close(),
        suppressedErrorsWatcher.close()
      ]);

      rebuildAndRewatch();
    }
  );
}

function watchConfiguration(
  options,
  {reviewElmJson, reviewElmJsonPath},
  rebuildAndRewatch
) {
  if (!reviewElmJsonPath || !options.watchConfig) return;

  const configurationPaths = reviewElmJson['source-directories']
    .map(
      (directory) => path.resolve(options.userSrc(), directory) + '/**/*.elm'
    )
    .concat([reviewElmJsonPath])
    .map(removeWindowsSeparators);

  const configurationWatcher = chokidar
    .watch(configurationPaths, {ignoreInitial: true})
    .on('change', async () => {
      await configurationWatcher.close();

      if (options.report !== 'json') {
        if (!options.debug) {
          clearConsole();
        }

        console.log(
          'Your configuration has changed. Restarting elm-review with the new one.'
        );
      }

      rebuildAndRewatch();
    });

  return configurationWatcher;
}

function clearConsole() {
  process.stdout.write(
    process.platform === 'win32'
      ? '\u001B[2J\u001B[0f'
      : '\u001B[2J\u001B[3J\u001B[H'
  );
}

function removeWindowsSeparators(string) {
  return string.replace(/.:/, '').replace(/\\/g, '/');
}

module.exports = {
  watchFiles,
  watchConfiguration
};

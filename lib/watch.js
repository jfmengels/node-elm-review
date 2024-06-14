const path = require('path');
const chokidar = require('chokidar');
const Debug = require('./debug');
const FS = require('./fs-wrapper');
const Runner = require('./runner');
const AppState = require('./state');
const Anonymize = require('./anonymize');
const OsHelpers = require('./os-helpers');
const SuppressedErrors = require('./suppressed-errors');

/**
 * @typedef { import("fs").FSWatcher } FSWatcher
 * @typedef { import("./types/options").ReviewOptions } ReviewOptions
 * @typedef { import("./types/app").App } App
 * @typedef { import("./types/watch").WatchOptions } WatchOptions
 * @typedef { import("./types/content").ApplicationElmJson } ApplicationElmJson
 * @typedef { import("./types/content").ElmJsonData } ElmJsonData
 * @typedef { import("./types/content").ElmFile } ElmFile
 * @typedef { import("./types/content").ExtraFileRequest } ExtraFileRequest
 * @typedef { import("./types/content").SourceDirectories } SourceDirectories
 * @typedef { import("./types/path").Path } Path
 */

let isFlushingStdio = false;

/** @type {ReturnType<typeof setTimeout> | undefined} */
let suppressedErrorsTimeout;

/**
 *
 * @param {ReviewOptions} options
 * @param {WatchOptions} watchOptions
 * @param {() => void} rebuildAndRewatch
 * @param {(err: Error) => void} onError
 * @returns {void}
 */
function watchFiles(
  options,
  {
    app,
    elmJsonData,
    elmFiles,
    sourceDirectories,
    reviewElmJson,
    reviewElmJsonPath,
    requestedExtraFiles
  },
  rebuildAndRewatch,
  onError
) {
  AppState.filesWereUpdated(elmFiles);

  let elmJsonContent = elmJsonData.project;

  /** @type {() => void} */
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
    .watch(OsHelpers.makePathOsAgnostic(options.elmJsonPath), {
      ignoreInitial: true,
      disableGlobbing: true
    })
    .on('change', async () => {
      const newValue = await FS.readJsonFile(options.elmJsonPath);
      if (JSON.stringify(newValue) !== JSON.stringify(elmJsonContent)) {
        elmJsonContent = newValue;
        runReview = () => {};
        clearTimeout(suppressedErrorsTimeout);
        await Promise.all([
          elmJsonWatcher.close(),
          readmeWatcher.close(),
          fileWatcher.close(),
          extraFilesWatchers.forEach((watcher) => watcher.close()),
          suppressedErrorsWatcher.close(),
          configurationWatcher && configurationWatcher.close()
        ]);

        if (options.report !== 'json') {
          if (!options.debug) {
            clearConsole();
          }

          // TODO Detect what has changed and only re-load the necessary parts.
          // We do some of this work in `autofix.js` already.
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

  const readmeWatcher = createReadmeWatcher(options, app, runReview, onError);

  const fileWatcher = createFileWatcher(
    options,
    app,
    runReview,
    onError,
    sourceDirectories
  );

  const extraFilesWatchers = requestedExtraFiles.map((request) =>
    createExtraFilesWatcher(options, app, runReview, onError, request)
  );

  const suppressedErrorsWatcher = createSuppressedFilesWatcher(
    options,
    app,
    onError
  );

  const configurationWatcher = watchConfiguration(
    options,
    reviewElmJson,
    reviewElmJsonPath,
    async () => {
      runReview = () => {};

      clearTimeout(suppressedErrorsTimeout);
      await Promise.all([
        elmJsonWatcher.close(),
        readmeWatcher.close(),
        fileWatcher.close(),
        extraFilesWatchers.forEach((watcher) => watcher.close()),
        suppressedErrorsWatcher.close()
      ]);

      rebuildAndRewatch();
    }
  );
}

/**
 * @param {ReviewOptions} options
 * @param {ApplicationElmJson} reviewElmJson
 * @param {Path | null} reviewElmJsonPath
 * @param {() => void} rebuildAndRewatch
 * @returns {FSWatcher | undefined} Function to close the watcher
 */
function watchConfiguration(
  options,
  reviewElmJson,
  reviewElmJsonPath,
  rebuildAndRewatch
) {
  if (!reviewElmJsonPath || !options.watchConfig) return;

  const configurationPaths = reviewElmJson['source-directories']
    .map(
      /**
       * @param {Path} directory
       * @returns {string}
       */
      (directory) => path.resolve(options.userSrc(), directory) + '/**/*.elm'
    )
    .concat([reviewElmJsonPath])
    .map(OsHelpers.makePathOsAgnostic);

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

/** Create a watcher for the README.md file
 *
 * @param {ReviewOptions} options
 * @param {App} app
 * @param {() => void} runReview
 * @param {(err: Error) => void} onError
 * @return {FSWatcher}
 */
function createReadmeWatcher(options, app, runReview, onError) {
  return chokidar
    .watch(OsHelpers.makePathOsAgnostic(options.readmePath), {
      ignoreInitial: true,
      disableGlobbing: true
    })
    .on('add', async () => {
      Debug.log('README.md has been added');

      const readme = {
        path: options.readmePath,
        content: await FS.readFile(options.readmePath)
      };

      AppState.readmeChanged(readme);
      app.ports.collectReadme.send(readme);
      runReview();
    })
    .on('change', async () => {
      const readme = {
        path: options.readmePath,
        content: await FS.readFile(options.readmePath)
      };
      const readmeHasChanged = AppState.readmeChanged(readme);
      if (readmeHasChanged) {
        Debug.log('README.md has been changed');

        app.ports.collectReadme.send(readme);
      }

      if (readmeHasChanged || options.report === 'json') {
        runReview();
      }
    })
    .on('error', onError);
}

/** Create a watcher for Elm files
 *
 * @param {ReviewOptions} options
 * @param {App} app
 * @param {() => void} runReview
 * @param {(err: Error) => void} onError
 * @param {SourceDirectories} sourceDirectories
 * @return {FSWatcher}
 */
function createFileWatcher(
  options,
  app,
  runReview,
  onError,
  sourceDirectories
) {
  return chokidar
    .watch(
      sourceDirectories.map(
        /**
         * @param {Path} directory
         * @returns {string} glob
         */
        (directory) => OsHelpers.makePathOsAgnostic(`${directory}/**/*.elm`)
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
      const relativePath = OsHelpers.makePathOsAgnostic(
        path.relative(process.cwd(), absolutePath)
      );

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

      const newSource = await FS.readFile(relativePath);

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
      const relativePath = OsHelpers.makePathOsAgnostic(
        path.relative(process.cwd(), absolutePath)
      );

      let elmFile = AppState.getFileFromMemoryCache(relativePath);
      if (!elmFile) {
        elmFile = {
          path: relativePath,
          source: '',
          ast: null
        };
      }

      const newSource = await FS.readFile(relativePath);
      const hasChanged = elmFile.source !== newSource;

      if (hasChanged) {
        Debug.log(
          `File ${Anonymize.path(options, relativePath)} has been changed`
        );

        // NOTE: Mutates the file cache
        elmFile.source = newSource;
        elmFile.ast = null;
        app.ports.collectFile.send(elmFile);
      }

      if (hasChanged || options.report === 'json') {
        runReview();
      }
    })
    .on('unlink', (absolutePath) => {
      const relativePath = OsHelpers.makePathOsAgnostic(
        path.relative(process.cwd(), absolutePath)
      );
      Debug.log(
        `File ${Anonymize.path(options, relativePath)} has been removed`
      );

      app.ports.removeFile.send(relativePath);
      runReview();
    })
    .on('error', onError);
}

/** Create a watcher for Elm files
 *
 * @param {ReviewOptions} options
 * @param {App} app
 * @param {() => void} runReview
 * @param {(err: Error) => void} onError
 * @param {ExtraFileRequest} request
 * @return {FSWatcher}
 */
function createExtraFilesWatcher(options, app, runReview, onError, request) {
  return chokidar
    .watch(
      request.files.map(
        ({pattern, included}) =>
          (included ? '' : '!') + OsHelpers.makePathOsAgnostic(pattern)
      ),
      {
        ignored: request.excludedDirectories,
        ignoreInitial: true
      }
    )
    .on('add', async (absolutePath) => {
      const relativePath = OsHelpers.makePathOsAgnostic(
        path.relative(process.cwd(), absolutePath)
      );

      const newSource = await FS.readFile(relativePath);
      Debug.log(
        `Extra file ${Anonymize.path(options, relativePath)} has been added`
      );

      app.ports.collectExtraFiles.send({[relativePath]: newSource});
      runReview();
    })
    .on('change', async (absolutePath) => {
      const relativePath = OsHelpers.makePathOsAgnostic(
        path.relative(process.cwd(), absolutePath)
      );

      const newSource = await FS.readFile(relativePath);
      Debug.log(
        `Extra file ${Anonymize.path(options, relativePath)} has been changed`
      );

      app.ports.collectExtraFiles.send({[relativePath]: newSource});
      runReview();
    })
    .on('unlink', (absolutePath) => {
      const relativePath = OsHelpers.makePathOsAgnostic(
        path.relative(process.cwd(), absolutePath)
      );
      Debug.log(
        `Extra file ${Anonymize.path(options, relativePath)} has been removed`
      );

      app.ports.removeFile.send(relativePath);
      runReview();
    })
    .on('error', onError);
}

/** Create a watcher for Elm files
 *
 * @param {ReviewOptions} options
 * @param {App} app
 * @param {(err: Error) => void} onError
 * @return {FSWatcher}
 */
function createSuppressedFilesWatcher(options, app, onError) {
  function updateSuppressedErrors() {
    // TODO Write last save time for each of these in appstate, and compare with the last update time
    // that is given as argument to this function. If possible, don't do anything.
    if (suppressedErrorsTimeout) {
      clearTimeout(suppressedErrorsTimeout);
    }

    suppressedErrorsTimeout = setTimeout(async () => {
      const suppressedErrors = await SuppressedErrors.read(options);
      // TODO Avoid doing anything if suppressed errors haven't changed
      //    It's likely this program's fault for changing anything anyway
      Debug.log('Suppressed errors have been added');
      app.ports.updateSuppressedErrors.send(suppressedErrors);
    }, 20);
  }

  return chokidar
    .watch(
      OsHelpers.makePathOsAgnostic(
        `${options.suppressedErrorsFolder()}/*.json`
      ),
      {ignoreInitial: true}
    )
    .on('add', updateSuppressedErrors)
    .on('change', updateSuppressedErrors)
    .on('unlink', updateSuppressedErrors)
    .on('error', onError);
}

function clearConsole() {
  process.stdout.write(
    process.platform === 'win32'
      ? '\u001B[2J\u001B[0f'
      : '\u001B[2J\u001B[3J\u001B[H'
  );
}

module.exports = {
  watchFiles,
  watchConfiguration
};

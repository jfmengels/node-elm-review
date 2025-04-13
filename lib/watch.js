/**
 * @import {FSWatcher} from 'fs';
 * @import {ReviewOptions} from './types/options';
 * @import {ReviewApp} from './types/app';
 * @import {WatchOptions} from './types/watch';
 * @import {ApplicationElmJson, ElmJson, ExtraFileRequest, SourceDirectories} from './types/content';
 * @import {Path} from './types/path';
 */
const path = require('node:path');
// TODO(@lishaduck) [engine:node@>=19.1]: Use `fs.watch` (or `@parcel/watcher`).
const chokidar = require('chokidar');
const Anonymize = require('./anonymize');
const Debug = require('./debug');
const FS = require('./fs-wrapper');
const Runner = require('./runner');
const AppState = require('./state');
const SuppressedErrors = require('./suppressed-errors');

let isFlushingStdio = false;

/** @type {ReturnType<typeof setTimeout> | undefined} */
let suppressedErrorsTimeout;

/**
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
    .watch(options.elmJsonPath, {
      ignoreInitial: true,
      disableGlobbing: true
    })
    .on('change', async () => {
      const newValue = /** @type {ElmJson} */ (
        await FS.readJsonFile(options.elmJsonPath)
      );
      if (JSON.stringify(newValue) !== JSON.stringify(elmJsonContent)) {
        elmJsonContent = newValue;
        runReview = () => {};
        clearTimeout(suppressedErrorsTimeout);

        await Promise.all(
          [
            elmJsonWatcher,
            readmeWatcher,
            fileWatcher,
            ...extraFilesWatchers,
            suppressedErrorsWatcher,
            configurationWatcher
          ].map(async (watcher) => await watcher?.close())
        );

        if (options.report !== 'json') {
          if (!options.debug) {
            clearConsole();
          }

          // TODO(@jfmengels): Detect what has changed and only re-load the necessary parts.
          //   We do some of this work in `autofix.js` already.
          Debug.log(
            'Your `elm.json` has changed. Restarting elm-review.',
            options.debug
          );
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
      await Promise.all(
        [
          elmJsonWatcher,
          readmeWatcher,
          fileWatcher,
          ...extraFilesWatchers,
          suppressedErrorsWatcher
        ].map(async (watcher) => {
          await watcher?.close();
        })
      );

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

  const configurationPaths = [
    ...reviewElmJson['source-directories'].map(
      /**
       * @param {Path} directory
       * @returns {string}
       */
      (directory) => path.resolve(options.userSrc(), directory) + '/**/*.elm'
    ),
    reviewElmJsonPath
  ];

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

/**
 * Create a watcher for the README.md file
 *
 * @param {ReviewOptions} options
 * @param {ReviewApp} app
 * @param {() => void} runReview
 * @param {(err: Error) => void} onError
 * @returns {FSWatcher}
 */
function createReadmeWatcher(options, app, runReview, onError) {
  return chokidar
    .watch(options.readmePath, {
      ignoreInitial: true,
      disableGlobbing: true
    })
    .on('add', async () => {
      Debug.log('README.md has been added', options.debug);

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
        Debug.log('README.md has been changed', options.debug);

        app.ports.collectReadme.send(readme);
      }

      if (readmeHasChanged || options.report === 'json') {
        runReview();
      }
    })
    .on('error', onError);
}

/**
 * Create a watcher for Elm files
 *
 * @param {ReviewOptions} options
 * @param {ReviewApp} app
 * @param {() => void} runReview
 * @param {(err: Error) => void} onError
 * @param {SourceDirectories} sourceDirectories
 * @returns {FSWatcher}
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
        (directory) => `${directory}/**/*.elm`
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
      const relativePath = path.relative(options.cwd, absolutePath);

      Debug.log(
        `File ${Anonymize.path(options, relativePath)} has been added`,
        options.debug
      );

      let elmFile = AppState.getFileFromMemoryCache(relativePath);

      const isNewFile = !elmFile;

      if (elmFile === undefined) {
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
      const relativePath = path.relative(options.cwd, absolutePath);

      const elmFile = AppState.getFileFromMemoryCache(relativePath) ?? {
        path: relativePath,
        source: '',
        ast: null
      };

      const newSource = await FS.readFile(relativePath);
      const hasChanged = elmFile.source !== newSource;

      if (hasChanged) {
        Debug.log(
          `File ${Anonymize.path(options, relativePath)} has been changed`,
          options.debug
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
      const relativePath = path.relative(options.cwd, absolutePath);
      Debug.log(
        `File ${Anonymize.path(options, relativePath)} has been removed`,
        options.debug
      );

      app.ports.removeFile.send(relativePath);
      runReview();
    })
    .on('error', onError);
}

/**
 * Create a watcher for Elm files
 *
 * @param {ReviewOptions} options
 * @param {ReviewApp} app
 * @param {() => void} runReview
 * @param {(err: Error) => void} onError
 * @param {ExtraFileRequest} request
 * @returns {FSWatcher}
 */
function createExtraFilesWatcher(options, app, runReview, onError, request) {
  return chokidar
    .watch(
      request.files.map(
        ({pattern, included}) => (included ? '' : '!') + pattern
      ),
      {
        ignored: request.excludedDirectories,
        ignoreInitial: true
      }
    )
    .on('add', async (absolutePath) => {
      const relativePath = path.relative(options.cwd, absolutePath);

      const newSource = await FS.readFile(relativePath);
      Debug.log(
        `Extra file ${Anonymize.path(options, relativePath)} has been added`,
        options.debug
      );

      app.ports.collectExtraFiles.send({[relativePath]: newSource});
      runReview();
    })
    .on('change', async (absolutePath) => {
      const relativePath = path.relative(options.cwd, absolutePath);

      const newSource = await FS.readFile(relativePath);
      Debug.log(
        `Extra file ${Anonymize.path(options, relativePath)} has been changed`,
        options.debug
      );

      app.ports.collectExtraFiles.send({[relativePath]: newSource});
      runReview();
    })
    .on('unlink', (absolutePath) => {
      const relativePath = path.relative(options.cwd, absolutePath);
      Debug.log(
        `Extra file ${Anonymize.path(options, relativePath)} has been removed`,
        options.debug
      );

      app.ports.removeFile.send(relativePath);
      runReview();
    })
    .on('error', onError);
}

/**
 * Create a watcher for Elm files
 *
 * @param {ReviewOptions} options
 * @param {ReviewApp} app
 * @param {(err: Error) => void} onError
 * @returns {FSWatcher}
 */
function createSuppressedFilesWatcher(options, app, onError) {
  /**
   * @returns {void}
   */
  function updateSuppressedErrors() {
    // TODO(@jfmengels): Write last save time for each of these in appstate,
    //   and compare with the last update time that is given as argument to
    //   this function. If possible, don't do anything.
    if (suppressedErrorsTimeout) {
      clearTimeout(suppressedErrorsTimeout);
    }

    suppressedErrorsTimeout = setTimeout(async () => {
      const suppressedErrors = await SuppressedErrors.read(options);
      // TODO(@jfmengels): Avoid doing anything if suppressed errors haven't
      //   changed. It's likely this program's fault for changing anything anyway.
      Debug.log('Suppressed errors have been added', options.debug);
      app.ports.updateSuppressedErrors.send(suppressedErrors);
    }, 20);
  }

  return chokidar
    .watch(`${options.suppressedErrorsFolder()}/*.json`, {ignoreInitial: true})
    .on('add', updateSuppressedErrors)
    .on('change', updateSuppressedErrors)
    .on('unlink', updateSuppressedErrors)
    .on('error', onError);
}

/**
 * @returns {void}
 */
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

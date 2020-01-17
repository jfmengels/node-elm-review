const util = require('util');
const path = require('path');
const fs = require('fs-extra');
const chokidar = require('chokidar');
const cache = require('./cache');
const runner = require('./runner');
const dependencies = require('./dependencies');

const fsReadFile = util.promisify(fs.readFile);
const fsReadJson = util.promisify(fs.readJson);

function watch(
  options,
  {
    app,
    elmJson,
    elmVersion,
    elmFiles,
    sourcesDirectories,
    reviewElmJson,
    reviewElmJsonPath
  },
  rebuildAndRewatch,
  onError
) {
  elmFiles.forEach(file => {
    cache.elmFilesCacheForWatch.push({...file});
  });
  let elmJsonContent = elmJson;

  const runReview = () => {
    runner.runReview(options, app).catch(onError);
  };

  // This makes sure that any stdin input is removed before prompting the user.
  // That way, when the user presses Enter in watch mode when there is no report yet,
  // a proposed fix will not automatically be applied.
  process.stdin.on('readable', () => {
    // Use a loop to make sure we read all available data.
    while (process.stdin.read() !== null) {
      // Do nothing
    }
  });

  const elmJsonWatcher = chokidar
    .watch(removeWindowsSeparators(options.elmJsonPath), {ignoreInitial: true})
    .on('change', async () => {
      const newValue = await fsReadJson(options.elmJsonPath);
      if (newValue !== elmJsonContent) {
        elmJsonContent = newValue;

        app.ports.collectElmJson.send(newValue);
        const projectDependencies = await dependencies.collect(
          newValue,
          elmVersion
        );
        app.ports.collectDependencies.send(projectDependencies);
        runReview();
      }
    });

  const fileWatcher = chokidar
    .watch(
      sourcesDirectories.map(directory =>
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
    .on('add', async absolutePath => {
      const relativePath = path.relative(process.cwd(), absolutePath);
      let elmFile = cache.elmFilesCacheForWatch.find(
        file => file.path === relativePath
      );
      if (!elmFile) {
        elmFile = {
          path: relativePath
        };
        cache.elmFilesCacheForWatch.push(elmFile);
      }

      const newSource = await fsReadFile(relativePath, 'utf8');

      if (elmFile.source !== newSource) {
        if (options.debug) {
          console.log(`File ${relativePath} has been added`);
        }

        elmFile.source = newSource;
        elmFile.ast = null;
        app.ports.collectFile.send(elmFile);
        runReview();
      }
    })
    .on('change', async absolutePath => {
      const relativePath = path.relative(process.cwd(), absolutePath);
      const elmFile = cache.elmFilesCacheForWatch.find(
        file => file.path === relativePath
      );
      if (!elmFile) {
        return;
      }

      const newSource = await fsReadFile(relativePath, 'utf8');

      if (elmFile.source !== newSource) {
        if (options.debug) {
          console.log(`File ${relativePath} has been changed`);
        }

        elmFile.source = newSource;
        elmFile.ast = null;
        app.ports.collectFile.send(elmFile);
        runReview();
      }
    })
    .on('unlink', absolutePath => {
      const relativePath = path.relative(process.cwd(), absolutePath);
      if (options.debug) {
        console.log(`File ${relativePath} has been removed`);
      }

      app.ports.removeFile.send(relativePath);
      runReview();
    })
    .on('error', onError);

  const configurationPaths = reviewElmJson['source-directories']
    .map(directory => path.resolve(options.userSrc(), directory) + '/**/*.elm')
    .concat([reviewElmJsonPath])
    .map(removeWindowsSeparators);

  const configurationWatcher = chokidar
    .watch(configurationPaths, {ignoreInitial: true})
    .on('change', async () => {
      await Promise.all([
        configurationWatcher.close(),
        elmJsonWatcher.close(),
        fileWatcher.close(),
        configurationWatcher.close()
      ]);

      clearConsole();
      console.log(
        'Your configuration has changed. Restarting elm-review with the new one.'
      );
      rebuildAndRewatch();
    });
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

module.exports = watch;

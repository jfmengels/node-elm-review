const util = require('util');
const path = require('path');
const fs = require('fs-extra');
const chokidar = require('chokidar');
const runner = require('./runner');

const fsReadFile = util.promisify(fs.readFile);

function watch(options, {app, elmFiles, sourcesDirectories}, onError) {
  const elmFilesCache = elmFiles.map(file => ({...file}));
  const onChange = () => {
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

  chokidar
    .watch(sourcesDirectories.map(directory => `${directory}/**/*.elm`), {
      ignored: ['node_modules', 'elm-stuff', '.*'],
      ignoreInitial: true
    })
    .on('add', absolutePath =>
      console.log(`File ${absolutePath} has been changed`)
    )
    .on('change', async absolutePath => {
      const relativePath = path.relative(process.cwd(), absolutePath);
      const elmFile = elmFilesCache.find(file => file.path === relativePath);
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
        onChange();
      }
    })
    .on('unlink', absolutePath =>
      console.log(`File ${absolutePath} has been removed`)
    )
    .on('error', onError);
}

module.exports = watch;

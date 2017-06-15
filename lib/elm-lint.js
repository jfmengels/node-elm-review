// @flow

process.title = 'elm-lint';

process.on('uncaughtException', function(error) {
  if (/ an argument in Javascript/.test(error)) {
    // Handle arg mismatch between js and elm code. Expected message from Elm:
    // "You are giving module `Main` an argument in JavaScript.
    // This module does not take arguments though! You probably need to change the
    // initialization code to something like `Elm.Test.Generated.Main.fullscreen()`]"
    console.error('Error starting the node-test-runner.');
    console.error(
      "Please check your Javascript 'elm-test' and Elm 'node-test-runner' package versions are compatible"
    );
    process.exit(1);
  } else {
    console.error('Unhandled exception while running the tests:', error);
    process.exit(1);
  }
});

const path = require('path');
const _ = require('lodash');
const glob = require('glob');
const fs = require('fs-extra');
const spawn = require('cross-spawn');
const minimist = require('minimist');
const compile = require('node-elm-compiler').compile;
const runner = require('./runner');

const generatedCodeDir = path.resolve(
  path.join('elm-stuff', 'generated-code', 'jfmengels', 'elm-lint')
);

const args = minimist(process.argv.slice(2), {
  alias: {
    compiler: 'c',
    help: 'h',
    watch: 'w'
  },
  boolean: ['warn', 'version', 'help', 'watch'],
  string: ['compiler']
});

const defaultGlob = '**/*.elm';

function getFiles(filename) {
  if (!fs.existsSync(filename)) {
    return [];
  }
  if (fs.lstatSync(filename).isDirectory()) {
    return _.flatMap(
      glob.sync('/' + defaultGlob, {
        root: filename,
        nocase: true,
        ignore: '/**/elm-stuff/**',
        nodir: true
      }),
      resolveFilePath
    );
  }
  return [path.resolve(filename)];
}

// Recursively search directories for *.elm files, excluding elm-stuff/
function resolveFilePath(filename) {
  // Exclude everything having anything to do with elm-stuff
  return getFiles(filename).filter(candidate => !candidate.split(path.sep).includes('elm-stuff'));
}

function globify(filename) {
  return glob.sync(filename, {nocase: true, ignore: '**/elm-stuff/**', nodir: false});
}

function globifyWithRoot(root, filename) {
  return glob.sync(filename, {root: root, nocase: true, ignore: '**/elm-stuff/**', nodir: false});
}

function getElmFilePaths(filePathArgs) {
  if (filePathArgs.length > 0) {
    return _.flatMap(filePathArgs, globify);
  }

  const root = path.join(path.resolve(process.cwd()));
  return globifyWithRoot(root, '**/*.elm');
}

function getPathToMake(args) {
  if (args.compiler === undefined) {
    return undefined;
  }

  if (!args.compiler) {
    console.error('The --compiler option must be given a path to an elm-make executable.');
    process.exit(1);
  }
  return args.compiler;
}

const pathToMake = getPathToMake(args);

if (args.help) {
  const exampleGlob = path.join('tests', '**', '*.elm');
  function printUsage(str) {
    console.log(`Usage: ${process.title} ${str}\n`);
  }

  [
    `[FILES] # Run linting on given files. Default is '${defaultGlob}'`,
    '[--compiler /path/to/compiler] # Run linting with given Elm compiler',
    '[--version] # Print version string and exit',
    '[--watch] # Run linting on file changes'
  ].forEach(printUsage);

  process.exit(1);
}

if (args.version) {
  console.log(require('../package.json').version);
  process.exit(0);
}

const compileOptions = {
  output: path.resolve(path.join(generatedCodeDir, 'elmLintOutput.js')),
  verbose: args.verbose,
  yes: true,
  spawn: spawnCompiler,
  pathToMake: pathToMake,
  warn: args.warn,
  processOpts: {}
};

function runLinting(testFile) {
  const compileProcess = compile([testFile], compileOptions);

  compileProcess.on('close', function(exitCode) {
    if (exitCode === 0) {
      return readAndEval(compileOptions.output);
    }
    console.error('Compilation failed for', testFile);
    if (!args.watch) {
      process.exit(exitCode);
    }
  });
}

function readAndEval(dest) {
  fs.readFile(dest, {encoding: 'utf8'}, function(readErr, compiledElmCode) {
    if (readErr) {
      console.error(
        'The test run failed because it could not read the compiled Elm code:\n\n',
        readErr
      );

      if (!args.watch) {
        process.exit(1);
      }
    }

    try {
      runner.evalElmCode(args, compiledElmCode);
    } catch (err) {
      console.error(
        'The test run failed because of a runtime exception encountered when evaluating the compiled Elm code:\n\n',
        err
      );

      if (!args.watch) {
        process.exit(1);
      }
    }
  });
}

function spawnCompiler(cmd, args, opts) {
  var compilerOpts = _.defaults(
    {stdio: [process.stdin, process.stdout /* 'ignore' */, process.stderr]},
    opts
  );

  return spawn(cmd, args, compilerOpts);
}

function runElmLint() {
  const filePathArgs = args._.length > 0 ? args._ : [];
  const relativeElmFile = getElmFilePaths(filePathArgs);
  const elmFiles = _.flatMap(relativeElmFile, resolveFilePath);

  if (elmFiles.length === 0) {
    console.error('Could not find any files to lint.');
    process.exit(1);
  }

  console.log(elmFiles)
}

module.exports = runElmLint;

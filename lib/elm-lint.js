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
const pify = require('pify');
const fs = require('fs-extra');
const pEvent = require('p-event');
const spawn = require('cross-spawn');
const minimist = require('minimist');
const compile = require('node-elm-compiler').compile;
const runner = require('./runner');

const readFile = pify(fs.readFile);

const defaultLintConfigFile = 'LintConfig.elm';
const generatedCodeDir = path.join(
  '.',
  'elm-stuff',
  'generated-code',
  'jfmengels',
  'elm-lint',
  'custom-binary'
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

if (args.help) {
  const exampleGlob = path.join('tests', '**', '*.elm');
  function printUsage(str) {
    console.log(`Usage: ${process.title} ${str}\n`);
  }

  [
    `[FILES] # Run linting on given files. Default is '${defaultGlob}' (TO BE IMPLEMENTED)`,
    '[--compiler /path/to/compiler] # Run linting with given Elm compiler',
    '[--version] # Print version string and exit',
    '[--watch] # Run linting on file changes (TO BE IMPLEMENTED)'
  ].forEach(printUsage);

  process.exit(1);
}

if (args.version) {
  console.log(require('../package.json').version);
  process.exit(0);
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
//
// const compileOptions = {
//   output: path.resolve(path.join(generatedCodeDir, 'elmLintOutput.js')),
//   verbose: args.verbose,
//   yes: true,
//   spawn: spawnCompiler,
//   pathToMake: pathToMake,
//   warn: args.warn,
//   processOpts: {}
// };
//
// function runLinting(testFile) {
//   const compileProcess = compile([testFile], compileOptions);
//
//   compileProcess.on('close', function(exitCode) {
//     if (exitCode === 0) {
//       return readAndEval(compileOptions.output);
//     }
//     console.error('Compilation failed for', testFile);
//     if (!args.watch) {
//       process.exit(exitCode);
//     }
//   });
// }
//
// function readAndEval(dest) {
//   fs.readFile(dest, {encoding: 'utf8'}, function(readErr, compiledElmCode) {
//     if (readErr) {
//       console.error(
//         'The test run failed because it could not read the compiled Elm code:\n\n',
//         readErr
//       );
//
//       if (!args.watch) {
//         process.exit(1);
//       }
//     }
//
//     try {
//       runner.evalElmCode(args, compiledElmCode);
//     } catch (err) {
//       console.error(
//         'The test run failed because of a runtime exception encountered when evaluating the compiled Elm code:\n\n',
//         err
//       );
//
//       if (!args.watch) {
//         process.exit(1);
//       }
//     }
//   });
// }
//
function spawnCompiler(cmd, args, opts) {
  const compilerOpts = _.defaults(
    {stdio: [process.stdin, process.stdout /* 'ignore' */, process.stderr]},
    opts
  );

  return spawn(cmd, args, compilerOpts);
}
//
// function compileConfiguration(destDirectory, _elmPackage) {
//   const elmPackage = _.assign({
//     dependencies: []
//   }, _elmPackage);
//   console.log(JSON.stringify(elmPackage, null, 4));
//   return readFile('./' + defaultLintConfigFile, 'utf8');
// }
//
// function readElmPackageJson() {
//   try {
//     return fs.readJsonSync('./elm-package.json');
//   } catch (err) {
//     throw new Error('Error reading elm-package.json: ' + err.message)
//   }
// }
//
// function runElmLint() {
//   // const filePathArgs = args._.length > 0 ? args._ : [];
//   const filePathArgs = [];
//   const elmPackage = readElmPackageJson();
//   const relativeElmFiles = getElmFilePaths(filePathArgs);
//   const elmFiles = _.flatMap(relativeElmFiles, resolveFilePath);
//
//   if (elmFiles.length === 0) {
//     console.error('Could not find any files to lint.');
//     process.exit(1);
//   }
//   return compileConfiguration(generatedCodeDir, elmPackage)
//     // return Promise.all(
//     //   elmFiles.map(file =>
//     //     readFile(file.absolutePath, 'utf8').then(content => {
//     //       return _.assign({}, file, {content});
//     //     })
//     //   )
//     // )
//     .then(console.log)
//     .catch(console.error);
// }

function createTemplateProject(dest) {
  const templateSrc = path.join(__dirname, '../template');
  fs.copySync(templateSrc, dest, {overwrite: false});
  fs.copySync(path.join(process.cwd(), 'LintConfig.elm'), path.join(dest, 'src/LintConfig.elm'), {
    overwrite: false
  });
}

function installNodeModules(cwd) {
  console.log('Installing node_modules');
  spawn.sync('npm', ['install', '-y'], {
    cwd: cwd,
    stdio: 'inherit'
  });
}

function compileElmProject(dest, binary) {
  console.log('Compiling linter');
  const compileOptions = {
    cwd: dest,
    output: binary,
    verbose: args.verbose,
    yes: true,
    spawn: spawnCompiler,
    pathToMake: pathToMake,
    warn: args.warn,
    processOpts: {}
  };

  const compileProcess = compile(['src/LintApp.elm'], compileOptions);
  return pEvent(compileProcess, 'close');
}

function runLinting(dest) {
  console.log('Run linting binary');
  spawn.sync('node', [path.join(dest, 'runner.js')], {
    cwd: process.cwd(),
    stdio: 'inherit'
  });
}

function initializeProject(dest, binary) {
  createTemplateProject(dest);
  installNodeModules(dest);
  return compileElmProject(dest, binary)
  .then(() => {
    runLinting(dest);
  });
}

function runElmLint() {
  const dest = path.join(process.cwd(), generatedCodeDir);
  const binary = path.resolve(dest, 'compiledLintApp.js');
  return initializeProject(dest, binary);
}

function errorHandler(err) {
  console.error(err.message);
  process.exit(1);
}

module.exports = () => {
  try {
    runElmLint().catch(errorHandler);
  } catch (err) {
    errorHandler(err);
  }
};

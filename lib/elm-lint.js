// @flow

process.title = 'elm-lint';

function errorHandler(err) {
  console.error(err.message || err); // eslint-disable-line no-console
  process.exit(1);
}

process.on('uncaughtException', errorHandler);

const path = require('path');
const _ = require('lodash');
const fs = require('fs-extra');
const pEvent = require('p-event');
const spawn = require('cross-spawn');
const minimist = require('minimist');
const compile = require('node-elm-compiler').compile;
const init = require('./init')

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
    help: 'h',
    watch: 'w'
  },
  boolean: ['warn', 'version', 'help', 'watch']
});

const defaultGlob = '**/*.elm';

function printUsage(str) {
  console.log(`Usage: ${process.title} ${str}\n`); // eslint-disable-line no-console
}

if (args.help) {
  [
    init.description,
    `[FILES] # Run linting on given files. Default is '${defaultGlob}' (TO BE IMPLEMENTED)`,
    '[--compiler /path/to/compiler] # Run linting with given Elm compiler',
    '[--version] # Print version string and exit',
    '[--watch] # Run linting on file changes (TO BE IMPLEMENTED)'
  ].forEach(printUsage);

  process.exit(1);
}

if (args.version) {
  console.log(require('../package.json').version); // eslint-disable-line no-console
  process.exit(0);
}

if (args._[0] == 'init') {
  init.initializeProject()
  process.exit(0);
}

function spawnCompiler(cmd, args, opts) {
  const compilerOpts = _.defaults({stdio: [process.stdin, 'ignore', process.stderr]}, opts);

  return spawn(cmd, args, compilerOpts);
}

function createTemplateProject(dest) {
  const templateSrc = path.join(__dirname, '../template');
  fs.copySync(templateSrc, dest, {overwrite: true});
  fs.copySync(path.join(process.cwd(), 'LintConfig.elm'), path.join(dest, 'src/LintConfig.elm'), {
    overwrite: true
  });

  const elmJsonPath = path.join(dest, 'elm.json');
  const pkg = fs.readJsonSync(elmJsonPath);
  pkg['source-directories'] = pkg['source-directories'].concat(
    path.relative(dest, process.cwd()) + '/src'
  );
  fs.writeFileSync(elmJsonPath, JSON.stringify(pkg, null, 4));
}

function npmInstall(cwd) {
  spawn.sync('npm', ['install', '-y'], {
    cwd: cwd,
    stdio: 'inherit'
  });
}

function compileElmProject(dest, binary) {
  const compileOptions = {
    spawn: spawnCompiler,
    cwd: dest,
    output: binary,
    verbose: false,
    warn: false,
    processOpts: {}
  };

  const compileProcess = compile(['src/LintApp.elm'], compileOptions);
  return pEvent(compileProcess, 'close');
}

function runLinting(dest) {
  const res = spawn.sync('node', [path.join(dest, 'runner.js')], {
    cwd: process.cwd(),
    stdio: 'inherit'
  });
  if (res.status !== 0) {
    process.exit(res.status);
  }
}

function initializeProject(dest, binary) {
  createTemplateProject(dest);
  npmInstall(dest);
  return compileElmProject(dest, binary).then(() => {
    runLinting(dest);
  });
}

function runElmLint() {
  const dest = path.join(process.cwd(), generatedCodeDir);
  const binary = path.resolve(dest, 'compiledLintApp.js');
  return initializeProject(dest, binary);
}

module.exports = () => {
  try {
    runElmLint().catch(errorHandler);
  } catch (err) {
    errorHandler(err);
  }
};

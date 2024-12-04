#!/bin/node
/* eslint n/no-process-exit: "off" -- WIP */
import {execSync} from 'node:child_process';
import * as fs from 'node:fs';
import * as path from 'node:path';
import {fileURLToPath} from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const CMD = 'elm-review --no-color';
const TMP = path.join(__dirname, 'temporary');
const ELM_HOME = path.join(TMP, 'elm-home');
const SNAPSHOTS = path.join(__dirname, 'run-snapshots');
/** @type {string | undefined} */
const SUBCOMMAND = process.argv[2];

/**
 * @param {string} data
 * @returns {string}
 */
const replaceScript = (data) => {
  const localPath = path.join(__dirname, '..');
  return data.replace(new RegExp(localPath, 'g'), '<local-path>');
};

const AUTH_GITHUB = process.env.AUTH_GITHUB ?? '';
const AUTH = AUTH_GITHUB ? ` --github-auth ${AUTH_GITHUB}` : '';

/**
 * @type {(arg0: string, arg1: string, arg2: string, arg3: string) => void}
 */
const runCommandAndCompareToSnapshot = (localCommand, title, args, file) => {
  console.log(`- ${title}: \u001B[34m elm-review --FOR-TESTS ${args}\u001B[0m`);
  if (!fs.existsSync(path.join(SNAPSHOTS, file))) {
    console.error(
      `\n  \u001B[31mThere is no snapshot recording for \u001B[33m${file}\u001B[31m\nRun \u001B[33m\n    npm run test-run-record -s\n\u001B[31mto generate it.\u001B[0m`
    );
    process.exit(1);
  }

  const output = execSync(
    `${localCommand}${AUTH} --FOR-TESTS ${args} || true`,
    {encoding: 'utf8', stdio: 'pipe'}
  );
  const replacedOutput = replaceScript(output);
  fs.writeFileSync(path.join(TMP, file), replacedOutput);

  const diff = execSync(
    `diff '${path.join(TMP, file)}' '${path.join(SNAPSHOTS, file)}' || true`,
    {encoding: 'utf8', stdio: 'pipe'}
  );
  if (diff) {
    console.error(
      `\u001B[31m  ERROR\n  I found a different output than expected:\u001B[0m`
    );
    console.error(`\n    \u001B[31mExpected:\u001B[0m\n`);
    console.error(fs.readFileSync(path.join(SNAPSHOTS, file), 'utf8'));
    console.error(`\n    \u001B[31mbut got:\u001B[0m\n`);
    console.error(fs.readFileSync(path.join(TMP, file), 'utf8'));
    console.error(`\n    \u001B[31mHere is the difference:\u001B[0m\n`);
    console.error(diff);
    process.exit(1);
  } else {
    console.log(`  \u001B[92mOK\u001B[0m`);
  }
};

/**
 * @type {(arg0: string, arg1: string, arg2: string, arg3: string) => void}
 */
const runAndRecord = (localCommand, title, args, file) => {
  console.log(
    `\u001B[33m- ${title}\u001B[0m: \u001B[34m elm-review --FOR-TESTS ${args}\u001B[0m`
  );
  const output = execSync(
    `ELM_HOME=${ELM_HOME} ${localCommand}${AUTH} --FOR-TESTS ${args} || true`,
    {encoding: 'utf8', stdio: 'pipe'}
  );
  const replacedOutput = replaceScript(output);
  fs.writeFileSync(path.join(SNAPSHOTS, file), replacedOutput);
};

/**
 * @param {string} localCommand
 * @param {string} title
 * @param {string} args
 * @param {string} file
 */
const createTestSuiteWithDifferentReportFormats = (
  localCommand,
  title,
  args,
  file
) => {
  createTest(localCommand, title, args, `${file}.txt`);
  createTest(
    localCommand,
    `${title} (JSON)`,
    `${args} --report=json`,
    `${file}-json.txt`
  );
  createTest(
    localCommand,
    `${title} (Newline delimited JSON)`,
    `${args} --report=ndjson`,
    `${file}-ndjson.txt`
  );
};

const createTestSuiteForHumanAndJson = (
  /** @type {string} */ localCommand,
  /** @type {string} */ title,
  /** @type {string} */ args,
  /** @type {string} */ file
) => {
  createTest(localCommand, title, args, `${file}.txt`);
  createTest(
    localCommand,
    `${title} (JSON)`,
    `${args} --report=json`,
    `${file}-json.txt`
  );
};

const initElmProject = () => {
  execSync('echo Y | npx --no-install elm init', {
    encoding: 'utf8',
    stdio: 'ignore'
  });
  fs.writeFileSync(
    'src/Main.elm',
    'module A exposing (..)\nimport Html exposing (text)\nmain = text "Hello!"\n'
  );
};

const checkFolderContents = (/** @type {string} */ folder) => {
  if (SUBCOMMAND === undefined) {
    console.log('  Checking generated files are the same');
    const diff = execSync(
      `diff -rq '${path.join(TMP, folder)}' '${path.join(
        SNAPSHOTS,
        folder
      )}' --exclude="elm-stuff" || true`,
      {encoding: 'utf8', stdio: 'pipe'}
    );
    if (diff) {
      console.error(
        `\u001B[31m  ERROR\n  The generated files are different:\u001B[0m`
      );
      console.error(diff);
      process.exit(1);
    } else {
      console.log(`  \u001B[92mOK\u001B[0m`);
    }
  }
};

const createAndGoIntoFolder = (/** @type {string} */ folder) => {
  const targetPath =
    SUBCOMMAND === undefined
      ? path.join(TMP, folder)
      : path.join(SNAPSHOTS, folder);
  fs.mkdirSync(targetPath, {recursive: true});
  process.chdir(targetPath);
};

const cleanUp = () => {
  const pathsToRemove = [
    TMP,
    path.join(__dirname, 'config-empty/elm-stuff'),
    path.join(__dirname, 'config-error-debug/elm-stuff'),
    path.join(__dirname, 'config-error-unknown-module/elm-stuff'),
    path.join(__dirname, 'config-for-outdated-elm-review-version/elm-stuff'),
    path.join(__dirname, 'config-for-salvageable-elm-review-version/elm-stuff'),
    path.join(__dirname, 'config-syntax-error/elm-stuff'),
    path.join(__dirname, 'config-that-triggers-no-errors/elm-stuff'),
    path.join(__dirname, 'config-unparsable-elmjson/elm-stuff'),
    path.join(__dirname, 'config-without-elm-review/elm-stuff'),
    path.join(__dirname, 'project-using-es2015-module/elm-stuff'),
    path.join(__dirname, 'project-with-errors/elm-stuff'),
    path.join(__dirname, 'project-with-suppressed-errors/elm-stuff')
  ];
  for (const p of pathsToRemove) fs.rmSync(p, {recursive: true, force: true});
};

cleanUp();
fs.mkdirSync(TMP, {recursive: true});

const createTest = (() => {
  if (SUBCOMMAND === 'record') {
    fs.rmSync(SNAPSHOTS, {recursive: true, force: true});
    fs.mkdirSync(SNAPSHOTS, {recursive: true});
    return runAndRecord;
  }

  console.log('\u001B[33m-- Testing runs\u001B[0m');
  return runCommandAndCompareToSnapshot;
})();

const PACKAGE_PATH = execSync('npm pack -s ../ | tail -n 1', {
  encoding: 'utf8',
  stdio: 'pipe'
}).trim();
console.log(`Package path is ${PACKAGE_PATH}`);
execSync(`npm install -g ${PACKAGE_PATH}`, {encoding: 'utf8', stdio: 'ignore'});

// Init

const INIT_PROJECT_NAME = 'init-project';

createAndGoIntoFolder(INIT_PROJECT_NAME);

initElmProject();
createTest(`echo Y | ${CMD}`, 'Init a new configuration', 'init', 'init.txt');

checkFolderContents(INIT_PROJECT_NAME);

// Init with template

const INIT_TEMPLATE_PROJECT_NAME = 'init-template-project';

createAndGoIntoFolder(INIT_TEMPLATE_PROJECT_NAME);

initElmProject();
createTest(
  `echo Y | ${CMD}`,
  'Init a new configuration using a template',
  'init --template jfmengels/elm-review-unused/example',
  'init-template.txt'
);

checkFolderContents(INIT_TEMPLATE_PROJECT_NAME);

// FIXES

const projectPath =
  SUBCOMMAND === undefined
    ? path.join(TMP, 'project to fix')
    : path.join(SNAPSHOTS, 'project to fix');
fs.rmSync(projectPath, {recursive: true, force: true});

// @ts-expect-error(TS2339): CI runs on a newer Node.js.
// eslint-disable-next-line @typescript-eslint/no-unsafe-call -- ^
fs.cpSync(path.join(__dirname, 'project-with-errors'), projectPath, {
  recursive: true
});
process.chdir(projectPath);

createTest(
  CMD,
  'Running with --fix-all-without-prompt',
  '--fix-all-without-prompt',
  'fix-all.txt'
);

if (SUBCOMMAND === undefined) {
  const filesToCheck = [
    'src/Main.elm',
    'src/Folder/Used.elm',
    'src/Folder/Unused.elm'
  ];
  for (const file of filesToCheck) {
    const diff = execSync(
      `diff '${path.join(TMP, 'project to fix', file)}' '${path.join(
        SNAPSHOTS,
        'project to fix',
        file
      )}' || true`,
      {encoding: 'utf8', stdio: 'pipe'}
    );
    if (diff) {
      console.error(`Running with --fix-all-without-prompt (looking at code)`);
      console.error(
        `\u001B[31m  ERROR\n  I found a different FIX output than expected for ${file}:\u001B[0m`
      );
      console.error(`\n    \u001B[31mHere is the difference:\u001B[0m\n`);
      console.error(
        execSync(
          `diff -py '${path.join(TMP, 'project to fix', file)}' '${path.join(
            SNAPSHOTS,
            'project to fix',
            file
          )}' || true`,
          {encoding: 'utf8', stdio: 'pipe'}
        )
      );
      process.exit(1);
    }
  }
}

// Suppress

process.chdir(path.join(__dirname, 'project-with-suppressed-errors'));
createTestSuiteForHumanAndJson(
  CMD,
  'Running with only suppressed errors should not report any errors',
  '',
  'suppressed-errors-pass'
);

fs.copyFileSync('fixed-elm.json', 'elm.json');
createTest(
  CMD,
  'Fixing all errors for an entire rule should remove the suppression file',
  '',
  'suppressed-errors-after-fixed-errors-for-rule.txt'
);
if (fs.existsSync('./review/suppressed/NoUnused.Dependencies.json')) {
  console.error(
    'Expected project-with-suppressed-errors/review/suppressed/NoUnused.Dependencies.json to have been deleted'
  );
  process.exit(1);
}

execSync('git checkout HEAD elm.json review/suppressed/ >/dev/null', {
  encoding: 'utf8',
  stdio: 'ignore'
});

fs.rmSync('src/OtherFile.elm');
createTest(
  CMD,
  'Fixing all errors for an entire rule should update the suppression file',
  '',
  'suppressed-errors-after-fixed-errors-for-file.txt'
);

const diff = execSync(
  'diff review/suppressed/NoUnused.Variables.json expected-NoUnused.Variables.json || true',
  {encoding: 'utf8', stdio: 'pipe'}
);
if (diff) {
  console.error(
    'Expected project-with-suppressed-errors/review/suppressed/NoUnused.Variables.json to have been updated'
  );
  process.exit(1);
}

execSync('git checkout HEAD src/OtherFile.elm review/suppressed/ >/dev/null', {
  encoding: 'utf8',
  stdio: 'ignore'
});

fs.copyFileSync('with-errors-OtherFile.elm', 'src/OtherFile.elm');
createTestSuiteForHumanAndJson(
  CMD,
  'Introducing new errors should show all related errors',
  '',
  'suppressed-errors-introducing-new-errors'
);
execSync('git checkout HEAD src/OtherFile.elm >/dev/null', {
  encoding: 'utf8',
  stdio: 'ignore'
});

process.chdir(__dirname);

// New-package

process.chdir(SUBCOMMAND === 'record' ? SNAPSHOTS : TMP);

const NEW_PACKAGE_NAME = 'elm-review-something';
const NEW_PACKAGE_NAME_FOR_NEW_RULE = `${NEW_PACKAGE_NAME}-for-new-rule`;

// FIXME(@lishaduck): Doesn't log the spinner.
createTest(
  CMD,
  'Creating a new package',
  `new-package --prefill some-author,${NEW_PACKAGE_NAME},BSD-3-Clause No.Doing.Foo --rule-type module`,
  'new-package.txt'
);

checkFolderContents(NEW_PACKAGE_NAME);

// New-rule (DEPENDS ON PREVIOUS STEP!)

// @ts-expect-error(TS2339): CI runs on a newer Node.js.
// eslint-disable-next-line @typescript-eslint/no-unsafe-call -- ^
fs.cpSync(NEW_PACKAGE_NAME, NEW_PACKAGE_NAME_FOR_NEW_RULE, {recursive: true});
process.chdir(NEW_PACKAGE_NAME_FOR_NEW_RULE);

createTest(
  CMD,
  'Creating a new rule',
  'new-rule SomeModuleRule --rule-type module',
  'new-module-rule.txt'
);
createTest(
  CMD,
  'Creating a new rule',
  'new-rule SomeProjectRule --rule-type project',
  'new-project-rule.txt'
);

checkFolderContents(NEW_PACKAGE_NAME_FOR_NEW_RULE);

process.chdir(path.join(__dirname, 'project-with-errors'));

createTestSuiteWithDifferentReportFormats(
  CMD,
  'Filter rules',
  '--rules NoUnused.Variables',
  'filter-rules'
);

createTest(
  CMD,
  'Filter rules with comma-separated list',
  '--rules NoUnused.Variables,NoUnused.Exports',
  'filter-rules-comma.txt'
);
createTest(
  CMD,
  'Filter rules with multiple --rules calls',
  '--rules NoUnused.Variables --rules NoUnused.Exports',
  'filter-rules-multiple-calls.txt'
);

createTestSuiteWithDifferentReportFormats(
  CMD,
  'Filter unknown rule',
  '--rules NoUnused.Unknown',
  'filter-unknown-rule'
);

createTest(
  CMD,
  'Ignore errors on directories',
  '--ignore-dirs src/Folder/',
  'ignore-dirs.txt'
);
createTest(
  CMD,
  'Ignore errors on files',
  '--ignore-files src/Folder/Unused.elm',
  'ignore-files.txt'
);

// Review with remote configuration

if (!process.env.CI && SUBCOMMAND === undefined) process.exit(0);

createTest(
  CMD,
  'Running using remote GitHub configuration',
  '--template jfmengels/elm-review-unused/example',
  'remote-configuration.txt'
);
createTest(
  CMD,
  'Running using remote GitHub configuration (no errors)',
  '--template jfmengels/node-elm-review/test/config-that-triggers-no-errors',
  'remote-configuration-no-errors.txt'
);
createTest(
  CMD,
  'Running using remote GitHub configuration without a path to the config',
  '--template jfmengels/test-node-elm-review',
  'remote-configuration-no-path.txt'
);

createTestSuiteWithDifferentReportFormats(
  CMD,
  'Using unknown remote GitHub configuration',
  '--template jfmengels/unknown-repo-123',
  'remote-configuration-unknown'
);
createTestSuiteWithDifferentReportFormats(
  CMD,
  'Using unknown remote GitHub configuration with a branch',
  '--template jfmengels/unknown-repo-123#some-branch',
  'remote-configuration-unknown-with-branch'
);
createTestSuiteWithDifferentReportFormats(
  CMD,
  'Using remote GitHub configuration with a non-existing branch and commit',
  '--template jfmengels/elm-review-unused/example#unknown-branch',
  'remote-configuration-with-unknown-branch'
);
createTestSuiteWithDifferentReportFormats(
  CMD,
  'Using remote GitHub configuration with existing repo but that does not contain template folder',
  '--template jfmengels/node-elm-review',
  'remote-configuration-with-absent-folder'
);
createTestSuiteWithDifferentReportFormats(
  CMD,
  'Using a remote configuration with a missing direct elm-review dependency',
  '--template jfmengels/node-elm-review/test/config-without-elm-review',
  'remote-without-elm-review'
);
createTestSuiteWithDifferentReportFormats(
  CMD,
  'Using a remote configuration with an outdated elm-review',
  '--template jfmengels/node-elm-review/test/config-for-outdated-elm-review-version',
  'remote-with-outdated-elm-review-version'
);
createTestSuiteWithDifferentReportFormats(
  CMD,
  'Using a remote configuration with an salvageable (outdated but compatible) elm-review',
  '--template jfmengels/node-elm-review/test/config-for-salvageable-elm-review-version',
  'remote-with-outdated-but-salvageable-elm-review-version'
);
createTestSuiteWithDifferentReportFormats(
  CMD,
  'Using a remote configuration with unparsable elm.json',
  '--template jfmengels/node-elm-review/test/config-unparsable-elmjson',
  'remote-configuration-with-unparsable-elmjson'
);
createTestSuiteWithDifferentReportFormats(
  CMD,
  'Using both --config and --template',
  '--config ../config-that-triggers-no-errors --template jfmengels/test-node-elm-review',
  'remote-configuration-with-config-flag'
);

fs.rmSync(TMP, {recursive: true, force: true});

#!/bin/node

/*
 * If you get errors like "rate limit exceeded",
 * you can run these tests with `AUTH_GITHUB=token`.
 * Follow this guide: <https://docs.github.com/en/github/authenticating-to-github/creating-a-personal-access-token> to create an API token,
 * and give it access to public repositories.
 */

/* eslint n/no-process-exit: "off" -- WIP */
import * as fsp from 'node:fs/promises';
import * as path from 'pathe';
import * as process from 'node:process';
import {fileURLToPath} from 'node:url';
import {glob} from 'tinyglobby';
import {$, cd} from 'zx';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

$.quiet = true;
$.stdio = 'pipe';
$.preferLocal = [path.join(__dirname, '../.node_modules/.bin/')];

const BIN = 'elm-review';
const TMP = path.join(__dirname, 'temporary');
const ELM_HOME = path.join(TMP, 'elm-home');
const SNAPSHOTS = path.join(__dirname, 'run-snapshots');
/** @type {string | undefined} */
const SUBCOMMAND = process.argv[2];

const nodeVersionOutput = await $`node --version`;
const nodeVersion = nodeVersionOutput.stdout.toString().slice(1).trim();
const nvmrc = await fsp.readFile('../.nvmrc');
const expectedVersion = nvmrc.toString().trim();

if (nodeVersion !== expectedVersion) {
  console.error(`INCORRECT NODE VERSION\n`);
  console.error(
    `You are using Node.js version ${nodeVersion} but you should be using ${expectedVersion}`
  );
  process.exit(1);
}

/**
 * @param {string} data
 * @returns {string}
 */
const replaceScript = (data) => {
  const localPath = path.join(__dirname, '..');
  return data
    .replace(
      // eslint-disable-next-line security/detect-non-literal-regexp -- Test code.
      new RegExp(localPath, 'g'),
      '<local-path>'
    )
    .replace(/\r\n/g, '\n');
};

const {AUTH_GITHUB, CI, REMOTE} = process.env;
const AUTH = AUTH_GITHUB === undefined ? [] : [`--github-auth=${AUTH_GITHUB}`];

const TEST_ARGS = ['--no-color', ...AUTH, '--FOR-TESTS'];

const TEST_ARGS_REGEX = /--no-color --github-auth=[\w:]+ /;

/**
 * @param {string} title
 * @param {string[]} args
 * @param {string} file
 * @param {string} [input]
 * @returns {Promise<void>}
 */
const runCommandAndCompareToSnapshot = async (title, args, file, input) => {
  const snapshotPath = path.join(SNAPSHOTS, file);
  const actualPath = path.join(TMP, file);
  const fullArgs = [...TEST_ARGS, ...args];

  const cmd = $({halt: true, input})`${BIN} ${fullArgs}`.nothrow();
  const censoredCommand = cmd.cmd.replace(TEST_ARGS_REGEX, '');

  process.stdout.write(`- ${title}: \u001B[34m ${censoredCommand}\u001B[0m`);
  try {
    await fsp.access(snapshotPath);
  } catch {
    console.error(
      `\n  \u001B[31mThere is no snapshot recording for \u001B[33m${file}\u001B[31m\nRun \u001B[33m\n    npm run test-run-record -s\n\u001B[31mto generate it.\u001B[0m`
    );
    process.exit(1);
  }

  const output = await cmd.run().text();
  const replacedOutput = replaceScript(output);
  await fsp.writeFile(actualPath, replacedOutput);

  const diff = await $`diff ${actualPath} ${snapshotPath}`.nothrow();
  if (diff.exitCode === 0) {
    console.log(`  \u001B[92mOK\u001B[0m`);
  } else {
    const [snapshot, actual] = await Promise.all([
      fsp.readFile(snapshotPath, 'utf8'),
      fsp.readFile(actualPath, 'utf8')
    ]);

    console.error(
      `\u001B[31m  ERROR\n  I found a different output than expected:\u001B[0m`
    );
    console.error(`\n    \u001B[31mExpected:\u001B[0m\n`);
    console.error(snapshot);
    console.error(`\n    \u001B[31mbut got:\u001B[0m\n`);
    console.error(actual);
    console.error(`\n    \u001B[31mHere is the difference:\u001B[0m\n`);
    console.error(diff.text());
    process.exit(1);
  }
};

/**
 * @param {string} title
 * @param {string[]} args
 * @param {string} file
 * @param {string} [input]
 * @returns {Promise<void>}
 */
const runAndRecord = async (title, args, file, input) => {
  const snapshotPath = path.join(SNAPSHOTS, file);
  const fullArgs = [...TEST_ARGS, ...args];

  const cmd = $({halt: true, input})`${BIN} ${fullArgs}`.nothrow();
  const censoredCommand = cmd.cmd.replace(TEST_ARGS_REGEX, '');

  console.log(
    `\u001B[33m- ${title}\u001B[0m: \u001B[34m ${censoredCommand}\u001B[0m`
  );

  $.env.ELM_HOME = ELM_HOME;

  const output = await cmd.run().text();
  const replacedOutput = replaceScript(output);
  await fsp.writeFile(snapshotPath, replacedOutput);
};

/**
 * @param {string} title
 * @param {string[]} args
 * @param {string} file
 * @returns {Promise<void>}
 */
const createTestSuiteWithDifferentReportFormats = async (title, args, file) => {
  await createTest(title, args, `${file}.txt`);
  await createTest(
    `${title} (JSON)`,
    [...args, '--report=json'],
    `${file}-json.txt`
  );
  await createTest(
    `${title} (Newline delimited JSON)`,
    [...args, '--report=ndjson'],
    `${file}-ndjson.txt`
  );
};

/**
 * @param {string} title
 * @param {string[]} args
 * @param {string} file
 * @returns {Promise<void>}
 */
const createTestSuiteForHumanAndJson = async (title, args, file) => {
  await createTest(title, args, `${file}.txt`);
  await createTest(
    `${title} (JSON)`,
    [...args, '--report=json'],
    `${file}-json.txt`
  );
};

const initElmProject = async () => {
  await $({input: 'Y'})`elm init`;
  await fsp.writeFile(
    'src/Main.elm',
    'module A exposing (..)\nimport Html exposing (text)\nmain = text "Hello!"\n'
  );
};

/**
 * @param {string} folder
 * @returns {Promise<void>}
 */
const checkFolderContents = async (folder) => {
  if (SUBCOMMAND === undefined) {
    process.stdout.write('  Checking generated files are the same');

    const snapshotFolder = path.join(SNAPSHOTS, folder);
    const actualFolder = path.join(TMP, folder);

    const diff =
      await $`diff -rq ${actualFolder} ${snapshotFolder} --exclude="elm-stuff"`.nothrow();
    if (diff.exitCode === 0) {
      console.log(`  \u001B[92mOK\u001B[0m`);
    } else {
      console.error(
        `\u001B[31m  ERROR\n  The generated files are different:\u001B[0m`
      );
      console.error(diff.text());
      process.exit(1);
    }
  }
};

/**
 * @param {string} folder
 * @returns {Promise<void>}
 */
const createAndGoIntoFolder = async (folder) => {
  const targetPath =
    SUBCOMMAND === undefined
      ? path.join(TMP, folder)
      : path.join(SNAPSHOTS, folder);
  await fsp.mkdir(targetPath, {recursive: true});
  cd(targetPath);
};

const cleanUp = async () => {
  const elmStuffs = await glob(path.join(__dirname, '/*/elm-stuff'), {
    ignore: path.join(__dirname, 'project-with-files-in-elm-stuff/'),
    onlyDirectories: true,
    expandDirectories: false
  });

  const pathsToRemove = [TMP, ...elmStuffs];

  await Promise.all(
    pathsToRemove.map(async (p) => {
      await fsp.rm(p, {recursive: true, force: true});
    })
  );
};

await cleanUp();
await fsp.mkdir(TMP, {recursive: true});

const createTest = await (async () => {
  if (SUBCOMMAND === 'record') {
    await fsp.rm(SNAPSHOTS, {recursive: true, force: true});
    await fsp.mkdir(SNAPSHOTS, {recursive: true});
    return runAndRecord;
  }

  console.log('\u001B[33m-- Testing runs\u001B[0m');
  return runCommandAndCompareToSnapshot;
})();

const PACK_OUTPUT = await $`npm pack -s ../`.pipe($`tail -n 1`);
const PACKAGE_PATH = PACK_OUTPUT.valueOf();
console.log(`Package path is \`${PACKAGE_PATH}\`.`);
await $`npm install -g ${PACKAGE_PATH}`;

// Init

const INIT_PROJECT_NAME = 'init-project';

await createAndGoIntoFolder(INIT_PROJECT_NAME);

await initElmProject();
await createTest('Init a new configuration', ['init'], 'init.txt', 'Y');

await checkFolderContents(INIT_PROJECT_NAME);

// Init with template

const INIT_TEMPLATE_PROJECT_NAME = 'init-template-project';

await createAndGoIntoFolder(INIT_TEMPLATE_PROJECT_NAME);

await initElmProject();
await createTest(
  'Init a new configuration using a template',
  ['init', '--template', 'jfmengels/elm-review-unused/example'],
  'init-template.txt'
);

await checkFolderContents(INIT_TEMPLATE_PROJECT_NAME);

// FIXES

const projectPath =
  SUBCOMMAND === undefined
    ? path.join(TMP, 'project to fix')
    : path.join(SNAPSHOTS, 'project to fix');
await fsp.rm(projectPath, {recursive: true, force: true});

// @ts-expect-error(TS2339): CI runs on a newer Node.js.
// eslint-disable-next-line @typescript-eslint/no-unsafe-call -- ^
await fsp.cp(path.join(__dirname, 'project-with-errors'), projectPath, {
  recursive: true
});
cd(projectPath);

await createTest(
  'Running with --fix-all-without-prompt',
  ['--fix-all-without-prompt'],
  'fix-all.txt'
);

if (SUBCOMMAND === undefined) {
  const filesToCheck = [
    'src/Main.elm',
    'src/Folder/Used.elm',
    'src/Folder/Unused.elm'
  ];

  /**
   * @param {string} file
   * @returns {Promise<void>}
   */
  const processFile = async (file) => {
    const actualFile = path.join(TMP, 'project to fix', file);
    const snapshotFile = path.join(SNAPSHOTS, 'project to fix', file);

    const diff = await $`diff ${actualFile} ${snapshotFile}`.nothrow();

    if (diff.exitCode !== 0) {
      console.error(`Running with --fix-all-without-prompt (looking at code)`);
      console.error(
        `\u001B[31m  ERROR\n  I found a different FIX output than expected for ${file}:\u001B[0m`
      );
      console.error(`\n    \u001B[31mHere is the difference:\u001B[0m\n`);
      console.error(
        await $`diff -py ${actualFile} ${snapshotFile}`.nothrow().text()
      );
      process.exit(1);
    }
  };

  await Promise.all(filesToCheck.map(processFile));
}

// Suppress

cd(path.join(__dirname, 'project-with-suppressed-errors'));
await createTestSuiteForHumanAndJson(
  'Running with only suppressed errors should not report any errors',
  [],
  'suppressed-errors-pass'
);

await fsp.copyFile('fixed-elm.json', 'elm.json');
await createTest(
  'Fixing all errors for an entire rule should remove the suppression file',
  [],
  'suppressed-errors-after-fixed-errors-for-rule.txt'
);

try {
  await fsp.access('./review/suppressed/NoUnused.Dependencies.json');

  // That should've thrown: thus the file still exists!?
  console.error(
    'Expected project-with-suppressed-errors/review/suppressed/NoUnused.Dependencies.json to have been deleted'
  );
  process.exit(1);
} catch {
  // File not accessible, hopefully it got deleted.
}

await $`git checkout HEAD elm.json review/suppressed/`;

await fsp.rm('src/OtherFile.elm');
await createTest(
  'Fixing all errors for an entire rule should update the suppression file',
  [],
  'suppressed-errors-after-fixed-errors-for-file.txt'
);

const diff =
  await $`diff review/suppressed/NoUnused.Variables.json expected-NoUnused.Variables.json`.nothrow();
if (diff.exitCode !== 0) {
  console.error(
    'Expected project-with-suppressed-errors/review/suppressed/NoUnused.Variables.json to have been updated'
  );
  process.exit(1);
}

await $`git checkout HEAD src/OtherFile.elm review/suppressed/`;

await fsp.copyFile('with-errors-OtherFile.elm', 'src/OtherFile.elm');
await createTestSuiteForHumanAndJson(
  'Introducing new errors should show all related errors',
  [],
  'suppressed-errors-introducing-new-errors'
);
await $`git checkout HEAD src/OtherFile.elm`;

cd(__dirname);

// New-package

cd(SUBCOMMAND === 'record' ? SNAPSHOTS : TMP);

const NEW_PACKAGE_NAME = 'elm-review-something';
const NEW_PACKAGE_NAME_FOR_NEW_RULE = `${NEW_PACKAGE_NAME}-for-new-rule`;

await createTest(
  'Creating a new package',
  [
    'new-package',
    '--prefill',
    `some-author,${NEW_PACKAGE_NAME},BSD-3-Clause`,
    'No.Doing.Foo',
    '--rule-type',
    'module'
  ],
  'new-package.txt'
);

await checkFolderContents(NEW_PACKAGE_NAME);

// New-rule (DEPENDS ON PREVIOUS STEP!)

// @ts-expect-error(TS2339): CI runs on a newer Node.js.
// eslint-disable-next-line @typescript-eslint/no-unsafe-call -- ^
await fsp.cp(NEW_PACKAGE_NAME, NEW_PACKAGE_NAME_FOR_NEW_RULE, {
  recursive: true
});
cd(NEW_PACKAGE_NAME_FOR_NEW_RULE);

await createTest(
  'Creating a new rule',
  ['new-rule', 'SomeModuleRule', '--rule-type', 'module'],
  'new-module-rule.txt'
);
await createTest(
  'Creating a new rule',
  ['new-rule', 'SomeProjectRule', '--rule-type', 'project'],
  'new-project-rule.txt'
);

await checkFolderContents(NEW_PACKAGE_NAME_FOR_NEW_RULE);

cd(path.join(__dirname, 'project-with-errors'));

await createTest(
  'Filter rules',
  ['--rules', 'NoUnused.Variables'],
  'filter-rules.txt'
);

await createTest(
  'Filter rules with comma-separated list',
  ['--rules', 'NoUnused.Variables,NoUnused.Exports'],
  'filter-rules-comma.txt'
);
await createTest(
  'Filter rules with multiple --rules calls',
  ['--rules', 'NoUnused.Variables', '--rules', 'NoUnused.Exports'],
  'filter-rules-multiple-calls.txt'
);

await createTestSuiteWithDifferentReportFormats(
  'Filter unknown rule',
  ['--rules', 'NoUnused.Unknown'],
  'filter-unknown-rule'
);

await createTest(
  'Ignore errors on directories',
  ['--ignore-dirs', 'src/Folder/'],
  'ignore-dirs.txt'
);

await createTest(
  'Ignore errors on files',
  ['--ignore-files', 'src/Folder/Unused.elm'],
  'ignore-files.txt'
);

// Review with remote configuration

if (
  (!REMOTE && !SUBCOMMAND && !CI && !AUTH_GITHUB) ||
  (CI && process.platform === 'win32')
) {
  process.exit(0);
}

await createTest(
  'Running using remote GitHub configuration',
  ['--template', 'jfmengels/elm-review-unused/example'],
  'remote-configuration.txt'
);
await createTest(
  'Running using remote GitHub configuration (no errors)',
  [
    '--template',
    'jfmengels/node-elm-review/test/config-that-triggers-no-errors'
  ],
  'remote-configuration-no-errors.txt'
);
await createTest(
  'Running using remote GitHub configuration without a path to the config',
  ['--template', 'jfmengels/test-node-elm-review'],
  'remote-configuration-no-path.txt'
);

await createTest(
  'Using unknown remote GitHub configuration',
  ['--template', 'jfmengels/unknown-repo-123'],
  'remote-configuration-unknown.txt'
);
await createTest(
  'Using unknown remote GitHub configuration with a branch',
  ['--template', 'jfmengels/unknown-repo-123#some-branch'],
  'remote-configuration-unknown-with-branch.txt'
);
await createTest(
  'Using remote GitHub configuration with a non-existing branch and commit',
  ['--template', 'jfmengels/elm-review-unused/example#unknown-branch'],
  'remote-configuration-with-unknown-branch.txt'
);
await createTest(
  'Using remote GitHub configuration with existing repo but that does not contain template folder',
  ['--template', 'jfmengels/node-elm-review'],
  'remote-configuration-with-absent-folder.txt'
);
await createTest(
  'Using a remote configuration with a missing direct elm-review dependency',
  ['--template', 'jfmengels/node-elm-review/test/config-without-elm-review'],
  'remote-without-elm-review.txt'
);
await createTest(
  'Using a remote configuration with an outdated elm-review',
  [
    '--template',
    'jfmengels/node-elm-review/test/config-for-outdated-elm-review-version'
  ],
  'remote-with-outdated-elm-review-version.txt'
);
await createTest(
  'Using a remote configuration with an salvageable (outdated but compatible) elm-review',
  [
    '--template',
    'jfmengels/node-elm-review/test/config-for-salvageable-elm-review-version'
  ],
  'remote-with-outdated-but-salvageable-elm-review-version.txt'
);
await createTest(
  'Using a remote configuration with unparsable elm.json',
  ['--template', 'jfmengels/node-elm-review/test/config-unparsable-elmjson'],
  'remote-configuration-with-unparsable-elmjson.txt'
);
await createTest(
  'Using both --config and --template',
  [
    '--config',
    '../config-that-triggers-no-errors',
    '--template=jfmengels/test-node-elm-review'
  ],
  'remote-configuration-with-config-flag.txt'
);

await fsp.rm(TMP, {recursive: true, force: true});

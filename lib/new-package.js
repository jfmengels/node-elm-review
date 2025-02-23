/**
 * @import {PackageJSON} from '@package-json/types' with {"resolution-mode": "import"};
 * @import {ApplicationElmJson, PackageElmJson} from './types/content';
 * @import {PackageTitle} from './types/new-package';
 * @import {Options, RuleType} from './types/options';
 * @import {Path} from './types/path';
 */
const childProcess = require('node:child_process');
const path = require('pathe');
const chalk = require('chalk');
const prompts = require('prompts');
const ErrorMessage = require('./error-message');
const FS = require('./fs-wrapper');
const Init = require('./init');
const MinVersion = require('./min-version');
const NewRule = require('./new-rule');
const Spinner = require('./spinner');

/**
 * @param {Options} options
 * @returns {Promise<void>}
 */
async function create(options) {
  const onCancelOptions = /** @satisfies {prompts.Options} */ ({
    onCancel: () => {
      canceled = true;
      return false;
    }
  });

  let canceled = false;

  /** @returns {Promise<string>} */
  const askForAuthorName = async () => {
    /** @type {{authorName: string}} */
    const prompt = await prompts(
      [
        {
          type: 'text',
          name: 'authorName',
          message: `Your GitHub username:`
        }
      ],
      onCancelOptions
    );

    return prompt.authorName;
  };

  const authorName =
    options.prefilledAnswers.authorName ?? (await askForAuthorName());

  if (canceled) {
    return;
  }

  const packageName =
    options.prefilledAnswers.packageName ?? (await askForPackageName());

  if (packageName === null) {
    return;
  }

  validatePackageName(packageName);

  /** @returns {Promise<string>} */
  const askForLicense = async () => {
    /** @type {{license: string}} */
    const prompt = await prompts(
      [
        {
          type: 'text',
          name: 'license',
          message: `The license for your package:`,
          initial: 'BSD-3-Clause'
        }
      ],
      onCancelOptions
    );

    return prompt.license;
  };

  const license = options.prefilledAnswers.license ?? (await askForLicense());

  if (canceled) {
    return;
  }

  const ruleName = options.newRuleName
    ? NewRule.validateRuleName(options.newRuleName)
    : await NewRule.askForRuleName();
  if (!ruleName) {
    return;
  }

  const ruleType = options.ruleType ?? (await NewRule.askForRuleType());
  if (!ruleType) {
    return;
  }

  await createProject(
    options,
    authorName,
    packageName,
    ruleName,
    ruleType,
    license
  );

  console.log(
    // prettier-ignore
    `\nAll done! ${chalk.green('✔')}

I created a ${chalk.yellow('maintenance/MAINTENANCE.md')} file which you should read in order to learn what the next steps are, and generally how to manage the project.

I hope you'll enjoy working with ${chalk.greenBright('elm-review')}! ❤️
`
  );
}

/**
 * @param {string} packageName
 * @returns {asserts packageName is PackageTitle}
 */
function validatePackageName(packageName) {
  if (!packageName.startsWith('elm-review-')) {
    throw new ErrorMessage.CustomError(
      'INVALID PACKAGE NAME',
      'The package name needs to start with "elm-review-".'
    );
  }
}

/**
 * @returns {Promise<string | null>}
 */
async function askForPackageName() {
  let canceled = false;

  /** @type {{packageName: string}} */
  const {packageName} = await prompts(
    {
      type: 'text',
      name: 'packageName',
      message: `The package name (starting with "elm-review-"):`
    },
    {
      onCancel: () => {
        canceled = true;
        return false;
      }
    }
  );

  if (canceled) {
    return null;
  }

  if (packageName.startsWith('elm-review-')) {
    return packageName;
  }

  console.log('The package name needs to start with "elm-review-".');
  return await askForPackageName();
}

/**
 * An up-to-date `elm-tooling.json` file.
 */
const elmToolingJson = {
  tools: {
    elm: '0.19.1',
    'elm-format': '0.8.7',
    'elm-json': '0.2.13'
  }
};

/**
 * @param {Path} dir
 * @param {string} fileName
 * @param {string} content
 * @returns {Promise<void>}
 */
async function writeFile(dir, fileName, content) {
  await FS.writeFile(path.join(dir, fileName), content);
}

/**
 * @param {Options} options
 * @param {string} authorName
 * @param {PackageTitle} packageName
 * @param {string} ruleName
 * @param {RuleType} ruleType
 * @param {string} license
 * @returns {Promise<void>}
 */
async function createProject(
  options,
  authorName,
  packageName,
  ruleName,
  ruleType,
  license
) {
  const dir = path.join(options.cwd, packageName);
  const ruleNameFolder = ruleName.split('.').slice(0, -1).join('/');

  try {
    await FS.mkdirp(path.join(dir, 'src', ruleNameFolder));
  } catch {}

  try {
    await FS.mkdirp(path.join(dir, 'tests', ruleNameFolder));
  } catch {}

  Spinner.setText('Adding elm.json', options.report, options.forTests);
  const packageElmJson = elmJson(authorName, packageName, ruleName, license);
  await writeFile(dir, 'elm.json', JSON.stringify(packageElmJson, null, 4));

  Spinner.succeedAndNowDo('Adding package.json', options.report);
  await writeFile(
    dir,
    'package.json',
    JSON.stringify(packageJson(options, packageName), null, 2)
  );

  Spinner.succeedAndNowDo('Adding elm-tooling.json', options.report);
  await writeFile(
    dir,
    'elm-tooling.json',
    JSON.stringify(elmToolingJson, null, 4)
  );

  Spinner.succeedAndNowDo('Adding README', options.report);
  await writeFile(dir, 'README.md', readme(authorName, packageName, ruleName));

  Spinner.succeedAndNowDo('Adding preview folder', options.report);
  const pathToPreview = path.join(options.cwd, packageName, 'preview');
  await Init.create(options, pathToPreview, 'ReviewConfigForExample.elm');

  // Adding package to the example's elm.json
  const previewElmJsonPath = path.join(pathToPreview, 'elm.json');
  const previewElmJson = /** @type {ApplicationElmJson} */ (
    await FS.readJsonFile(previewElmJsonPath)
  );
  previewElmJson['source-directories'] = [
    ...previewElmJson['source-directories'],
    '../src'
  ];
  await FS.writeFile(
    previewElmJsonPath,
    JSON.stringify(previewElmJson, null, 4)
  );

  // Adding rule to the preview's ReviewConfig
  const previewReviewConfigPath = path.join(
    pathToPreview,
    'src/ReviewConfig.elm'
  );
  const previewReviewConfig = await FS.readFile(previewReviewConfigPath);
  await FS.writeFile(
    previewReviewConfigPath,
    previewReviewConfig.replace(/RULENAME_TO_REPLACE/g, ruleName)
  );

  Spinner.succeedAndNowDo(`Adding rule - ${ruleName}`, options.report);

  await writeFile(
    dir,
    path.join('src', `${ruleName.split('.').join('/')}.elm`),
    NewRule.newSourceFile(`${authorName}/${packageName}`, ruleName, ruleType)
  );
  await writeFile(
    dir,
    path.join('tests', `${ruleName.split('.').join('/')}Test.elm`),
    NewRule.newTestFile(ruleName)
  );

  Spinner.succeedAndNowDo('Adding .gitignore', options.report);
  await writeFile(
    dir,
    '.gitignore',
    `node_modules/
elm-stuff/

# Editors
.idea/
ElmjutsuDumMyM0DuL3.elm
`
  );

  Spinner.succeedAndNowDo('Adding GitHub Actions', options.report);
  const githubDestFiles = path.join(dir, '.github/');
  await Promise.all([
    FS.mkdirp(path.join(githubDestFiles, 'ISSUE_TEMPLATE')),
    FS.mkdirp(path.join(githubDestFiles, 'workflows'))
  ]);
  await FS.copyFiles(
    path.join(__dirname, '../new-package/github/'),
    githubDestFiles,
    ['ISSUE_TEMPLATE/new-rule-idea.md', 'workflows/test.yml']
  );

  Spinner.succeedAndNowDo(
    `Adding LICENSE ${chalk.grey(`npx license ${license}`)}`,
    options.report
  );
  const licenseArgs = options.forTests ? '--name "Test User" --year 2020' : '';
  try {
    childProcess.execSync(
      // TODO(@lishaduck): Evaluate calling the API instead.
      `npx license ${license} --projectName "${authorName}/${packageName}" ${licenseArgs}`,
      {
        cwd: dir,
        stdio: ['ignore', 'ignore', 'pipe']
      }
    );
  } catch (error) {
    console.log(chalk.red('FAILED adding a license'));
    if (options.debug) {
      console.log(error);
    } else {
      console.log(error.message);
    }
  }

  Spinner.succeedAndNowDo('Adding elm-review configuration', options.report);
  await Init.createFromTemplate(
    options,
    {
      repoName: 'jfmengels/node-elm-review',
      pathToFolder: 'new-package/review-config-templates/2.3.0',
      reference: null
    },
    path.join(options.cwd, packageName, 'review')
  );

  Spinner.succeedAndNowDo('Adding maintenance scripts', options.report);
  const maintenancePath = path.join(options.cwd, packageName, 'maintenance');
  await FS.mkdirp(maintenancePath);
  await FS.copyFiles(
    path.join(__dirname, '../new-package/maintenance/'),
    maintenancePath,
    ['MAINTENANCE.md', 'update-examples-from-preview.js']
  );

  const packageTests = path.join(
    options.cwd,
    packageName,
    'elm-review-package-tests'
  );
  FS.mkdirpSync(path.join(packageTests, 'helpers'));
  await FS.copyFiles(
    path.join(__dirname, '../new-package/elm-review-package-tests'),
    packageTests,
    [
      'check-previews-compile.js',
      'check-examples-were-updated.js',
      'helpers/ansi.js',
      'helpers/find-configurations.js'
    ]
  );

  const checkPreviewsCompile = path.join(
    packageTests,
    'check-previews-compile.js'
  );
  const data = await FS.readFile(checkPreviewsCompile);
  const result = data.replace(/\/\/ @ts-ignore - Generated file.\n/, '');
  await FS.writeFile(checkPreviewsCompile, result, 'utf8');

  Spinner.succeed(undefined, options.report);
}

/**
 * @param {string} authorName
 * @param {PackageTitle} packageName
 * @param {string} ruleName
 * @param {string} license
 * @returns {PackageElmJson}
 */
function elmJson(authorName, packageName, ruleName, license) {
  return {
    type: 'package',
    name: `${authorName}/${packageName}`,
    summary: '',
    license,
    version: '1.0.0',
    'exposed-modules': [ruleName],
    'elm-version': '0.19.0 <= v < 0.20.0',
    dependencies: {
      'elm/core': '1.0.5 <= v < 2.0.0',
      'jfmengels/elm-review': MinVersion.supportedRange,
      'stil4m/elm-syntax': '7.2.9 <= v < 8.0.0'
    },
    'test-dependencies': {
      'elm-explorations/test': '2.0.1 <= v < 3.0.0'
    }
  };
}

/**
 * @param {string} authorName
 * @param {PackageTitle} packageName
 * @param {string} ruleName
 * @returns {string}
 */
function readme(authorName, packageName, ruleName) {
  return `# ${packageName}

Provides [\`elm-review\`](https://package.elm-lang.org/packages/jfmengels/elm-review/latest/) rules to REPLACEME.

## Provided rules

${NewRule.ruleDescription(`${authorName}/${packageName}`, '1.0.0', ruleName)}

## Configuration

\`\`\`elm
module ReviewConfig exposing (config)

import ${ruleName}
import Review.Rule exposing (Rule)

config : List Rule
config =
    [ ${ruleName}.rule
    ]
\`\`\`

## Try it out

You can try the example configuration above out by running the following command:

\`\`\`bash
elm-review --template ${authorName}/${packageName}/example
\`\`\`
`;
}

/**
 * @param {Options} options
 * @param {PackageTitle} packageName
 * @returns {PackageJSON}
 */
function packageJson(options, packageName) {
  return {
    name: packageName,
    private: true,
    scripts: {
      test: 'npm-run-all --print-name --silent --sequential test:make test:format test:run test:review test:package',
      'test:make': 'elm make --docs=docs.json',
      'test:format': 'elm-format src/ preview*/ tests/ --validate',
      'test:run': 'elm-test',
      'test:review': 'elm-review',
      'test:package': 'node elm-review-package-tests/check-previews-compile.js',
      'preview-docs': 'elm-doc-preview',
      'elm-bump':
        "npm-run-all --print-name --silent --sequential test bump-version 'test:review -- --fix-all-without-prompt' update-examples",
      'bump-version': '(yes | elm bump)',
      'update-examples': 'node maintenance/update-examples-from-preview.js',
      postinstall: 'elm-tooling install'
    },
    engines: {
      node: '>=14.21.3'
    },
    devDependencies: {
      'elm-doc-preview': '^5.0.5',
      'elm-review': `^${options.packageJsonVersion}`,
      'elm-test': '^0.19.1-revision12',
      'elm-tooling': '^1.15.1',
      'fs-extra': '^9.0.0',
      'npm-run-all': '^4.1.5',
      tinyglobby: '^0.2.10'
    }
  };
}

module.exports = {
  create,
  elmToolingJson
};

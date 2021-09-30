const path = require('path');
const childProcess = require('child_process');
const chalk = require('chalk');
const fs = require('fs-extra');
const prompts = require('prompts');
const elmToolingCli = require('elm-tooling');
const Init = require('./init');
const Spinner = require('./spinner');
const NewRule = require('./new-rule');
const MinVersion = require('./min-version');
const ErrorMessage = require('./error-message');

async function newPackage(options) {
  const onCancelOptions = {
    onCancel: () => {
      canceled = true;
      return false;
    }
  };

  let canceled = false;

  const authorName =
    options.prefilledAnswers.authorName ||
    (await prompts(
      [
        {
          type: 'text',
          name: 'authorName',
          message: `Your GitHub username:`
        }
      ],
      onCancelOptions
    ).then((a) => a.authorName));

  if (canceled) {
    return;
  }

  const packageName = options.prefilledAnswers.packageName
    ? validatePackageName(options.prefilledAnswers.packageName) ||
      options.prefilledAnswers.packageName
    : await askForPackageName();
  if (!packageName) {
    return;
  }

  const license =
    options.prefilledAnswers.license ||
    (await prompts(
      [
        {
          type: 'text',
          name: 'license',
          message: `The license for your package:`,
          initial: 'BSD-3-Clause'
        }
      ],
      onCancelOptions
    ).then((a) => a.license));

  if (canceled) {
    return;
  }

  const ruleName = options.newRuleName
    ? NewRule.validateRuleName(options.newRuleName) || options.newRuleName
    : await NewRule.askForRuleName(options);

  if (ruleName) {
    await createProject(options, authorName, packageName, ruleName, license);

    /* eslint-disable prettier/prettier */
    console.log(`\nAll done! ${chalk.green('✔')}

I created a ${chalk.yellow('maintenance/MAINTENANCE.md')} file which you should read in order to learn what the next steps are, and generally how to manage the project.

I hope you'll enjoy working with ${chalk.greenBright('elm-review')}! ❤️
`);
    /* eslint-enable prettier/prettier */
  }
}

function validatePackageName(packageName) {
  if (!packageName.startsWith('elm-review-')) {
    throw new ErrorMessage.CustomError(
      'INVALID PACKAGE NAME',
      'The package name needs to start with "elm-review-".'
    );
  }
}

async function askForPackageName() {
  let canceled = false;

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
  return askForPackageName();
}

function writeFile(dir, fileName, content) {
  fs.writeFileSync(path.join(dir, fileName), content);
}

async function createProject(
  options,
  authorName,
  packageName,
  ruleName,
  license
) {
  const dir = path.join(process.cwd(), packageName);
  const ruleNameFolder = ruleName.split('.').slice(0, -1).join('/');

  try {
    fs.mkdirpSync(path.join(dir, 'src', ruleNameFolder));
  } catch {}

  try {
    fs.mkdirpSync(path.join(dir, 'tests', ruleNameFolder));
  } catch {}

  Spinner.setText('Adding elm.json');
  const packageElmJson = elmJson(authorName, packageName, ruleName, license);
  writeFile(dir, 'elm.json', JSON.stringify(packageElmJson, null, 4));

  Spinner.succeedAndNowDo('Adding package.json');
  writeFile(
    dir,
    'package.json',
    JSON.stringify(packageJson(options, packageName), null, 2)
  );

  Spinner.succeedAndNowDo('Adding elm-tooling.json');
  const ignoreWriteStream = {write: () => {}};
  await elmToolingCli(['init'], {
    cwd: dir,
    stdout: ignoreWriteStream,
    stderr: ignoreWriteStream
  });

  Spinner.succeedAndNowDo('Adding README');
  writeFile(dir, 'README.md', readme(authorName, packageName, ruleName));

  Spinner.succeedAndNowDo('Adding preview folder');
  const pathToPreview = path.join(process.cwd(), packageName, 'preview');
  await Init.create(options, pathToPreview, 'ReviewConfigForExample.elm');

  // Adding package to the example's elm.json
  const previewElmJsonPath = path.join(pathToPreview, 'elm.json');
  const previewElmJson = fs.readJsonSync(previewElmJsonPath);
  previewElmJson['source-directories'] = previewElmJson[
    'source-directories'
  ].concat('../src');
  fs.writeFileSync(previewElmJsonPath, JSON.stringify(previewElmJson, null, 4));

  // Adding rule to the preview's ReviewConfig
  const previewReviewConfigPath = path.join(
    pathToPreview,
    'src/ReviewConfig.elm'
  );
  const previewReviewConfig = fs.readFileSync(previewReviewConfigPath, 'utf8');
  fs.writeFileSync(
    previewReviewConfigPath,
    previewReviewConfig.replace(/RULENAME_TO_REPLACE/g, ruleName)
  );

  Spinner.succeedAndNowDo(`Adding rule - ${ruleName}`);

  writeFile(
    dir,
    path.join('src', `${ruleName.split('.').join('/')}.elm`),
    NewRule.newSourceFile(`${authorName}/${packageName}`, ruleName)
  );
  writeFile(
    dir,
    path.join('tests', `${ruleName.split('.').join('/')}Test.elm`),
    NewRule.newTestFile(ruleName)
  );

  Spinner.succeedAndNowDo('Adding .gitignore');
  writeFile(
    dir,
    '.gitignore',
    `node_modules/
elm-stuff/

# Editors
.idea/
ElmjutsuDumMyM0DuL3.elm
`
  );

  Spinner.succeedAndNowDo('Adding GitHub Actions');
  fs.copySync(
    path.join(__dirname, '../new-package/github/'),
    path.join(dir, '.github/'),
    {overwrite: true}
  );

  Spinner.succeedAndNowDo(
    'Adding LICENSE',
    chalk.grey(`npx license ${license}`)
  );
  const licenseArgs = options.forTests ? '--name "Test User" --year 2020' : '';
  try {
    childProcess.execSync(
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

  Spinner.succeedAndNowDo('Adding elm-review configuration');
  await Init.createFromTemplate(
    options,
    {
      repoName: 'jfmengels/node-elm-review',
      pathToFolder: 'new-package/review-config-templates/2.3.0',
      reference: null
    },
    path.join(process.cwd(), packageName, 'review')
  );

  Spinner.succeedAndNowDo('Adding maintenance scripts');
  const maintenancePath = path.join(process.cwd(), packageName, 'maintenance');
  fs.mkdirpSync(maintenancePath);
  fs.copySync(
    path.join(__dirname, '../new-package/maintenance/'),
    maintenancePath,
    {
      overwrite: true
    }
  );

  const packageTests = path.join(
    process.cwd(),
    packageName,
    'elm-review-package-tests'
  );
  fs.mkdirpSync(packageTests);
  fs.copySync(
    path.join(__dirname, '../new-package/elm-review-package-tests/'),
    packageTests,
    {
      overwrite: true
    }
  );

  Spinner.succeed();
}

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
      'stil4m/elm-syntax': '7.2.1 <= v < 8.0.0'
    },
    'test-dependencies': {
      'elm-explorations/test': '1.2.2 <= v < 2.0.0'
    }
  };
}

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

function packageJson(options, packageName) {
  return {
    name: packageName,
    scripts: {
      test:
        'npm-run-all --print-name --silent --sequential test:make test:format test:run test:review test:package',
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
    dependencies: {
      'elm-doc-preview': '^5.0.3',
      'elm-review': `^${options.packageJsonVersion}`,
      'elm-test': '^0.19.1-revision6',
      'elm-tooling': '^1.4.1',
      'fs-extra': '9.0.0',
      glob: '7.1.6',
      'npm-run-all': '^4.1.5'
    }
  };
}

module.exports = newPackage;

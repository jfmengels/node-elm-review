const path = require('path');
const childProcess = require('child_process');
const chalk = require('chalk');
const fs = require('fs-extra');
const prompts = require('prompts');
const Init = require('./init');
const Spinner = require('./spinner');
const NewRule = require('./new-rule');
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
    console.log(`Here is what you still need to do:

1 Install the ${chalk.magentaBright('npm')} dependencies

    ${chalk.cyan('npm install')}    or    ${chalk.cyan('yarn')}

2. Initialize Git in your repository

    ${chalk.cyan('git init')}
    ${chalk.cyan('git add --all')}
    ${chalk.cyan('git commit --message="Initialize project"')}

When you create this repository on GitHub, consider adding the ${chalk.greenBright('elm-review')} topic to the repository.

3. Search and replace all the ${chalk.yellow('REPLACEME')} in the different files I have created by something relevant to your project or rules.

4. At all times, make sure that your example configuration is working.

5. Implement your rules!
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

  try {
    fs.mkdirpSync(path.join(dir, '.github/workflows'));
  } catch {}

  Spinner.setText('Adding elm.json');
  const packageElmJson = elmJson(authorName, packageName, ruleName, license);
  writeFile(dir, 'elm.json', JSON.stringify(packageElmJson, null, 4));

  Spinner.succeedAndNowDo('Adding package.json');
  writeFile(dir, 'package.json', JSON.stringify(packageJson(options), null, 2));

  Spinner.succeedAndNowDo('Adding README');
  writeFile(dir, 'README.md', readme(authorName, packageName, ruleName));

  Spinner.succeedAndNowDo('Adding preview folder');
  const pathToPreview = path.join(process.cwd(), packageName, 'preview');
  await Init.create(options, pathToPreview, 'ReviewConfigForExample.elm', []);

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
    path.join(__dirname, '../review-config-templates/github-action.yml'),
    path.join(dir, '.github/workflows/test.yml'),
    {overwrite: true}
  );
  // TODO GitHub actions - elm-review? elm-format?
  // TODO Add a document that explains things
  //   - Initial publish, subsequent publishes
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
  await Init.create(
    options,
    path.join(process.cwd(), packageName, 'review'),
    'NewPackageReviewConfig.elm',
    [
      'jfmengels/review-unused@2',
      'jfmengels/review-common@1',
      'jfmengels/review-debug@2',
      'jfmengels/review-documentation@1',
      'sparksp/elm-review-forbidden-words@1'
    ]
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

  Spinner.succeedAndNowDo('Adding maintenance scripts');
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
    summary: 'Provides elm-review rules to REPLACEME',
    license,
    version: '1.0.0',
    'exposed-modules': [ruleName],
    'elm-version': '0.19.0 <= v < 0.20.0',
    dependencies: {
      'elm/core': '1.0.2 <= v < 2.0.0',
      'jfmengels/elm-review': '2.0.0 <= v < 3.0.0',
      'stil4m/elm-syntax': '7.1.0 <= v < 8.0.0'
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

function packageJson(options) {
  return {
    scripts: {
      test:
        'elm make --docs=docs.json && elm-format src/ tests/ --validate && elm-test && elm-review && npm run package-tests -s',
      'package-tests':
        'node elm-review-package-tests/check-examples-compile.js',
      review: 'elm-review',
      'preview-docs': 'elm-doc-preview'
    },
    dependencies: {
      elm: '0.19.1-3',
      'elm-doc-preview': '^5.0.3',
      'elm-format': '0.8.3',
      'elm-review': `^${options.packageJsonVersion}`,
      'elm-test': '0.19.1-revision2',
      glob: '7.1.6',
      'fs-extra': '9.0.0'
    },
    published: false
  };
}

module.exports = newPackage;

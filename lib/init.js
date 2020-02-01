const path = require('path');
const chalk = require('chalk');
const fs = require('fs-extra');
const prompts = require('prompts');
const {getElmBinary, getElmVersion} = require('./elm-binary');
const templateDependencies = require('./template-dependencies');

async function initializeProject(options) {
  const directory = options.userSrc();
  const {accepted} = await prompts({
    type: 'confirm',
    name: 'accepted',
    message: `Would you like me to create ${chalk.yellow(
      'elm.json'
    )} and ${chalk.yellow('ReviewConfig.elm')} inside ${chalk.yellow(
      directory
    )}?`,
    initial: true
  });
  if (!accepted) {
    return;
  }

  try {
    fs.mkdirSync(directory);
  } catch (error) {}

  await createElmJson(options, directory);
  createReviewConfig(directory);
  console.log(
    `
All done! I have created a review project at ${chalk.green(
      (directory + '/').replace(/\/\//g, '/')
    )} for you.

You can now define your review configuration by editing ${chalk.green(
      path.join(directory, 'ReviewConfig.elm')
    )}.

I recommend you take a look at the following documents:
  - How to configure ${chalk.cyan('elm-review')}: ${chalk.underline(
      'https://github.com/jfmengels/elm-review/#Configuration'
    )}
  - When to write or enable a rule: ${chalk.underline(
    'https://github.com/jfmengels/elm-review/#when-to-write-or-enable-a-rule'
  )}
`
  );
}

async function createElmJson(options, directory) {
  const elmBinary = await getElmBinary(options);
  const elmVersion = await getElmVersion(elmBinary);

  const elmJson = {
    type: 'application',
    'source-directories': ['.'],
    'elm-version': elmVersion || '0.19.1',
    dependencies: {
      direct: {
        'elm/core': '1.0.2',
        'elm/json': '1.1.3'
      },
      indirect: {}
    },
    'test-dependencies': {
      direct: {},
      indirect: {}
    }
  };

  const pathToElmJson = path.join(directory, 'elm.json');
  fs.writeFileSync(pathToElmJson, JSON.stringify(elmJson, null, 4));
  await templateDependencies.add(pathToElmJson);
}

function createReviewConfig(directory) {
  const reviewConfigPath = path.join(__dirname, '../DefaultReviewConfig.elm');
  fs.copyFileSync(reviewConfigPath, path.join(directory, 'ReviewConfig.elm'), {
    overwrite: true
  });
}

module.exports = initializeProject;

const path = require('path');
const chalk = require('chalk');
const fs = require('fs-extra');
const prompts = require('prompts');
const {getElmBinary, getElmVersion} = require('./elm-binary');
const templateDependencies = require('./template-dependencies');

async function initializeProject(options) {
  const directory = options.initPath();
  const configDirectory = path.join(directory, 'src');
  const {accepted} = await prompts({
    type: 'confirm',
    name: 'accepted',
    message: `Would you like me to create ${chalk.yellow(
      'elm.json'
    )} and ${chalk.yellow('src/ReviewConfig.elm')} inside ${chalk.yellow(
      directory
    )}?`,
    initial: true
  });
  if (!accepted) {
    return;
  }

  try {
    fs.mkdirpSync(configDirectory);
  } catch (_) {}

  await createElmJson(options, directory);
  createReviewConfig(configDirectory);
  console.log(
    `
All done! I have created a review project at ${chalk.green(
      (directory + '/').replace(/\/\//g, '/')
    )} for you.

You can now define your review configuration by editing ${chalk.green(
      path.join(configDirectory, 'ReviewConfig.elm')
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
    'source-directories': ['src'],
    'elm-version': elmVersion || '0.19.1',
    dependencies: {
      direct: {},
      indirect: {}
    },
    'test-dependencies': {
      direct: {},
      indirect: {}
    }
  };

  const pathToElmJson = path.join(directory, 'elm.json');
  fs.writeFileSync(pathToElmJson, JSON.stringify(elmJson, null, 4));
  await templateDependencies.add(options, pathToElmJson);

  const elmJsonWithDeps = fs.readJsonSync(pathToElmJson);
  delete elmJsonWithDeps.dependencies.indirect['elm-explorations/test'];
  fs.writeFileSync(pathToElmJson, JSON.stringify(elmJsonWithDeps, null, 4));
}

function createReviewConfig(directory) {
  const reviewConfigPath = path.join(__dirname, '../DefaultReviewConfig.elm');
  fs.copyFileSync(reviewConfigPath, path.join(directory, 'ReviewConfig.elm'));
}

module.exports = initializeProject;

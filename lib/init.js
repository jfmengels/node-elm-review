const path = require('path');
const chalk = require('chalk');
const fs = require('fs-extra');
const prompts = require('prompts');
const {getElmBinary, getElmVersion} = require('./elm-binary');
const templateDependencies = require('./template-dependencies');

async function promptAndCreate(options) {
  const directory = options.initPath();

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

  await create(options, options.initPath(), 'DefaultReviewConfig.elm', []);

  console.log(
    `
All done! I have created a review project at ${chalk.green(
      (directory + '/').replace(/\/\//g, '/')
    )} for you.

You can now define your review configuration by editing ${chalk.green(
      path.join(directory, 'src/ReviewConfig.elm')
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

async function create(options, directory, template, additionalDeps) {
  const configDirectory = path.join(directory, 'src');

  try {
    fs.mkdirpSync(configDirectory);
  } catch (_) {}

  await createElmJson(options, directory, additionalDeps);
  createReviewConfig(configDirectory, template);
}

async function createElmJson(options, directory, additionalDeps) {
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
  await templateDependencies.add(pathToElmJson, additionalDeps);

  const elmJsonWithDeps = fs.readJsonSync(pathToElmJson);
  delete elmJsonWithDeps.dependencies.indirect['elm-explorations/test'];
  fs.writeFileSync(pathToElmJson, JSON.stringify(elmJsonWithDeps, null, 4));
}

function createReviewConfig(directory, template) {
  fs.copyFileSync(
    path.join(__dirname, '../review-config-templates/', template),
    path.join(directory, 'ReviewConfig.elm')
  );
}

module.exports = {
  create,
  promptAndCreate
};

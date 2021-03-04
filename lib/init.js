const path = require('path');
const chalk = require('chalk');
const fs = require('fs-extra');
const prompts = require('prompts');
const Anonymize = require('./anonymize');
const RemoteTemplate = require('./remote-template');
const {getElmBinary, getElmVersion} = require('./elm-binary');
const TemplateDependencies = require('./template-dependencies');

module.exports = {
  create,
  createFromTemplate,
  promptAndCreate
};

async function promptAndCreate(options) {
  const directory = options.initPath();

  if (options.template) {
    // Don't prompt when using template, the user likely knows what they are doing.
    await createFromTemplate(options, options.template, directory);
  } else {
    const {accepted} = await prompts({
      type: 'confirm',
      name: 'accepted',
      message: `Would you like me to create ${chalk.yellow(
        'elm.json'
      )} and ${chalk.yellow('src/ReviewConfig.elm')} inside ${chalk.yellow(
        Anonymize.path(options, directory)
      )}?`,
      initial: true
    });

    if (!accepted) {
      return;
    }

    await create(options, directory, 'DefaultReviewConfig.elm');
  }

  logInit(options, directory);
}

async function createFromTemplate(options, template, directory) {
  const configDirectory = path.join(directory, 'src');

  try {
    fs.mkdirpSync(configDirectory);
  } catch {}

  const commit = await RemoteTemplate.getRelevantCommit(options, template);
  const reviewElmJson = await RemoteTemplate.getRemoteElmJson(
    options,
    template,
    path.join(directory, 'elm.json'),
    commit
  );
  const reviewElmJsonWithReplacedParentDirectories = {
    ...reviewElmJson,
    'source-directories': reviewElmJson['source-directories'].map((dir) =>
      dir.split('..').join('parent')
    )
  };
  fs.writeFileSync(
    path.join(directory, 'elm.json'),
    JSON.stringify(reviewElmJsonWithReplacedParentDirectories, null, 4)
  );

  await RemoteTemplate.downloadSourceDirectories(
    options,
    template,
    commit,
    directory,
    reviewElmJson
  );
}

function logInit(options, directory) {
  console.log(
    `All done! I have created a review project at ${chalk.green(
      (Anonymize.path(options, directory) + '/').replace(/\/\//g, '/')
    )} for you.`
  );

  if (!options.template) {
    console.log(`
You can now define your review configuration by editing ${chalk.green(
      Anonymize.path(options, path.join(directory, 'src/ReviewConfig.elm'))
    )}.

I recommend you take a look at the following documents:
  - How to configure ${chalk.cyan('elm-review')}: ${chalk.underline(
      'https://github.com/jfmengels/elm-review/#Configuration'
    )}
  - When to write or enable a rule: ${chalk.underline(
    'https://github.com/jfmengels/elm-review/#when-to-write-or-enable-a-rule'
  )}
`);
  }
}

async function create(options, directory, template) {
  const configDirectory = path.join(directory, 'src');

  try {
    fs.mkdirpSync(configDirectory);
  } catch {}

  await createElmJson(options, directory);
  createReviewConfig(configDirectory, template);
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
  await TemplateDependencies.add(options, pathToElmJson);

  const elmJsonWithDeps = fs.readJsonSync(pathToElmJson);
  fs.writeFileSync(pathToElmJson, JSON.stringify(elmJsonWithDeps, null, 4));
}

function createReviewConfig(directory, template) {
  fs.copyFileSync(
    path.join(__dirname, '../init-templates/', template),
    path.join(directory, 'ReviewConfig.elm')
  );
}

const fs = require('graceful-fs');
const path = require('node:path');
// TODO [engine:node@>=16.7.0]: Use native `cp`.
const fsExtra = require('fs-extra');
const chalk = require('chalk');
const prompts = require('prompts');
const FS = require('./fs-wrapper');
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
    FS.mkdirpSync(configDirectory);
  } catch {}

  const commit = await RemoteTemplate.getRelevantCommit(options, template);
  const reviewElmJson = await RemoteTemplate.getRemoteElmJson(
    options,
    template,
    path.join(directory, 'elm.json'),
    commit,
    true
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
  const message = options.template
    ? templateInitMessage(options, directory)
    : regularInitMessage(options, directory);

  console.log(
    `All done! I have created a review project at ${chalk.green(
      (Anonymize.path(options, directory) + '/').replace(/\/\//g, '/')
    )} for you.

${message}

I recommend you take a look at the following documents:
  - How to configure ${chalk.cyan('elm-review')}: ${chalk.underline(
      'https://github.com/jfmengels/elm-review/#Configuration'
    )}
  - When to write or enable a rule: ${chalk.underline(
    'https://github.com/jfmengels/elm-review/#when-to-write-or-enable-a-rule'
  )}
${options.template ? templateRecommendation : ''}`
  );
}

function regularInitMessage(options, directory) {
  return `You can now define your review configuration by editing ${chalk.green(
    Anonymize.path(options, path.join(directory, 'src/ReviewConfig.elm'))
  )}.`;
}

const orange = chalk.keyword('orange');

function templateInitMessage(options, directory) {
  return `You chose to use someone's review configuration which can be great to get started
but don't forget to review the configuration to make sure it fits your needs,
both by removing rules you disagree with and by finding new rules to aid you.
You can do so by editing ${chalk.green(
    Anonymize.path(options, path.join(directory, 'src/ReviewConfig.elm'))
  )}.`;
}

const templateRecommendation = `
By starting out with this configuration, you may end up with too many errors to handle at once.
I recommend you use a mix of the following approaches:
  - Enable rules one by one by commenting them out at first
  - Use ${orange(
    'elm-review suppress'
  )} to suppress existing errors but prevent future ones (see ${orange(
  'elm-review suppress --help'
)}).
`;

async function create(options, directory, template) {
  const configDirectory = path.join(directory, 'src');

  try {
    FS.mkdirpSync(configDirectory);
  } catch {}

  await createElmJson(options, directory);
  createReviewConfig(configDirectory, template);
}

async function createElmJson(options, directory) {
  const elmBinary = await getElmBinary(options);
  const elmVersion = await getElmVersion(elmBinary);

  fs.writeFileSync(
    path.join(directory, 'elm.json'),
    JSON.stringify(
      TemplateDependencies.createNewReviewElmJson(options, elmVersion),
      null,
      4
    )
  );
}

function createReviewConfig(directory, template) {
  fsExtra.copyFileSync(
    path.join(__dirname, '../init-templates/', template),
    path.join(directory, 'ReviewConfig.elm')
  );
}

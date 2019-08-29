const path = require('path');
const chalk = require('chalk');
const fs = require('fs-extra');
const prompts = require('prompts');
const spawn = require('cross-spawn');
const getElmBinary = require('./elm-binary');
const dependencies = require('./dependencies');

async function initializeProject(args) {
  const directory = args.config || 'lint';
  const {accepted} = await prompts({
    type: 'confirm',
    name: 'accepted',
    message: `Would you like me to create ${chalk.yellow(
      'elm.json'
    )} and ${chalk.yellow('LintConfig.elm')} inside ${chalk.yellow(
      directory
    )}?`,
    initial: true
  });
  if (!accepted) {
    return;
  }

  try {
    fs.mkdirSync(path.join(process.cwd(), directory));
  } catch (error) {}

  await createElmJson(args, directory);
  createLintConfig(directory);
  console.log(
    `
All done! I have created a lint project at ${chalk.green(
      (directory + '/').replace(/\/\//g, '/')
    )} for you.

You can now define your lint configuration by editing ${chalk.green(
      path.join(directory, 'LintConfig.elm')
    )}.

I recommend you take a look at the following documents:
  - How to configure ${chalk.cyan('elm-lint')}: ${chalk.underline(
      'https://github.com/jfmengels/elm-lint/#Configuration'
    )}
  - When to write or enable a rule: ${chalk.underline(
    'https://github.com/jfmengels/elm-lint/#when-to-write-or-enable-a-rule'
  )}
`
  );
}

async function createElmJson(args, directory) {
  const version = await getElmVersion(args);
  const elmJson = {
    type: 'application',
    'source-directories': ['.'],
    'elm-version': version || '0.19.0',
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

  const pathToElmJson = path.join(process.cwd(), directory, 'elm.json');
  fs.writeFileSync(pathToElmJson, JSON.stringify(elmJson, null, 4));
  await dependencies.add(pathToElmJson);
}

async function getElmVersion(args) {
  const elmBinary = await getElmBinary(args);

  const result = spawn.sync(elmBinary, ['--version'], {
    silent: true,
    env: process.env
  });

  if (result.status !== 0) {
    return '0.19.0';
  }

  return trimVersion(result.stdout.toString());
}

function trimVersion(version) {
  const index = version.indexOf('-');
  if (index === -1) {
    return version.trim();
  }

  return version.slice(0, index).trim();
}

function createLintConfig(directory) {
  const lintConfigPath = path.join(__dirname, '../DefaultLintConfig.elm');
  fs.copyFileSync(
    lintConfigPath,
    path.join(process.cwd(), directory, 'LintConfig.elm'),
    {
      overwrite: true
    }
  );
}

const description = `init # Make your project lintable by creating a linting project`;

module.exports = {
  initializeProject,
  description
};

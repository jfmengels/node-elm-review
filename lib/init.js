const path = require('path');
const chalk = require('chalk');
const fs = require('fs-extra');
const spawn = require('cross-spawn');
const getElmBinary = require('./elm-binary');

async function initializeProject(args) {
  const folder = args['lint-folder'] || 'lint';
  try {
    fs.mkdirSync(path.join(process.cwd(), folder));
  } catch (error) {}

  await createElmJson(args, folder);
  createLintConfig(folder);
  console.log(
    `
All done! I have created a lint project at ${chalk.green(
      (folder + '/').replace(/\/\//g, '/')
    )} for you.

You can now define your lint configuration by editing ${chalk.green(
      path.join(folder, 'LintConfig.elm')
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

async function createElmJson(args, folder) {
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
  fs.writeFileSync(
    path.join(process.cwd(), folder, 'elm.json'),
    JSON.stringify(elmJson, null, 4)
  );
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

function createLintConfig(folder) {
  const lintConfigPath = path.join(__dirname, '../DefaultLintConfig.elm');
  fs.copyFileSync(
    lintConfigPath,
    path.join(process.cwd(), folder, 'LintConfig.elm'),
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

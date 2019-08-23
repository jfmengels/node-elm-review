const path = require('path');
const fs = require('fs-extra');

const lintConfigFile = 'LintConfig.elm';

function initializeProject() {
  fs.mkdirSync(path.join(process.cwd(), 'lint'));
  createElmJson();
  createLintConfig();
}

function createElmJson() {
  const elmJson = {
    type: 'application',
    'source-directories': ['.'],
    'elm-version': '0.19.0',
    dependencies: {
      direct: {
        'elm/core': '1.0.2'
      },
      indirect: {}
    },
    'test-dependencies': {
      direct: {},
      indirect: {}
    }
  };
  fs.writeFileSync(
    path.join(process.cwd(), 'lint/elm.json'),
    JSON.stringify(elmJson, null, 4)
  );
}

function createLintConfig() {
  const lintConfigPath = path.join(__dirname, '../DefaultLintConfig.elm');
  fs.copyFileSync(
    lintConfigPath,
    path.join(process.cwd(), 'lint', lintConfigFile),
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

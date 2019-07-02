const fs = require('fs')
const path = require('path')

const lintConfigFile = 'LintConfig.elm';

function initializeProject() {
const lintConfigPath = path.join(__dirname, '../DefaultLintConfig.elm');
fs.copySync(lintConfigPath, path.join(process.cwd(), lintConfigFile), {overwrite: true});
}

const description = `init # Make your project lintable by creating a ${lintConfigFile} file`

module.exports = {
  initializeProject,
  description
}

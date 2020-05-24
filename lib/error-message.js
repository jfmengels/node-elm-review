const chalk = require('chalk');
const stripAnsi = require('strip-ansi');

const create = (title, message, path) =>
  JSON.stringify({
    customElmReviewError: true,
    title,
    path,
    message
  });

const formatHuman = error =>
  `${chalk.green(
    `-- ${error.title} ${'-'.repeat(80 - error.title.length - 4)}`
  )}

${error.message.trim()}
`;

const formatJson = (error, defaultPath) => ({
  title: error.title,
  path: error.path || defaultPath,
  error: stripAnsi(error.message.trim())
});

module.exports = {
  create,
  formatHuman,
  formatJson
};

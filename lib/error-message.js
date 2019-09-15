const chalk = require('chalk');

const errorMessage = (title, body) =>
  `${chalk.green(`-- ${title} ${'-'.repeat(80 - title.length - 4)}`)}

${body.trim()}
`;

module.exports = errorMessage;

const path = require('path');
const chalk = require('chalk');
const ErrorMessage = require('./error-message');

const minimalVersion = {major: 2, minor: 1};

module.exports = {
  minimalVersion,
  validate
};

function validate(options, elmJsonPath, version) {
  const [major, minor] = version.split('.');

  if (
    Number.parseInt(major, 10) === minimalVersion.major &&
    Number.parseInt(minor, 10) >= minimalVersion.minor
  ) {
    // Configuration uses a compatible version of `elm-review`
    return;
  }

  if (options.template) {
    throw new ErrorMessage.CustomError(
      /* eslint-disable prettier/prettier */
        'UNSUPPORTED ELM-REVIEW VERSION',
`The template uses an unsupported version of ${chalk.greenBright('jfmengels/elm-review')}. It is using v${version}, but I need it to be ${minimalVersion.major}.${minimalVersion.minor}.0 <= v < ${minimalVersion.major + 1}.0.0.

Please inform the template author and kindly ask him to update his configuration, or make a pull request to help them out.`
        /* eslint-enable prettier/prettier */
    );
  }

  throw new ErrorMessage.CustomError(
    /* eslint-disable prettier/prettier */
'UNSUPPORTED ELM-REVIEW VERSION',
`You are using ${chalk.greenBright('jfmengels/elm-review')} v${version}, but I need it to be
${minimalVersion.major}.${minimalVersion.minor}.0 <= v < ${minimalVersion.major + 1}.0.0.

Please upgrade your version by running
${chalk.cyanBright(`npx elm-json install jfmengels/elm-review@${minimalVersion.major}`)} inside
of ${chalk.yellow(path.dirname(elmJsonPath))}.`
      /* eslint-enable prettier/prettier */
  );
}

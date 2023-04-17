const path = require('path');
const chalk = require('chalk');
const PathHelpers = require('./path-helpers');
const ErrorMessage = require('./error-message');

const minimalVersion = {major: 2, minor: 13};
/* eslint-disable prettier/prettier */
const supportedRange = `${minimalVersion.major}.${minimalVersion.minor}.0 <= v < ${minimalVersion.major + 1}.0.0`
/* eslint-enable prettier/prettier */

module.exports = {
  updateToAtLeastMinimalVersion,
  validate,
  supportedRange
};

function updateToAtLeastMinimalVersion(version) {
  const [major, minor] = version.split('.');

  if (Number.parseInt(major, 10) !== minimalVersion.major) {
    // Major version for which the configuration exists is not compatible
    // We'll return the version, and let following checks handle the problem
    return version;
  }

  if (Number.parseInt(minor, 10) >= minimalVersion.minor) {
    // User uses a more recent version of `jfmengels/elm-review`
    return version;
  }

  // User uses a less recent version of `jfmengels/elm-review`
  // And let's hope the patch version of the package is not buggy...
  return `${minimalVersion.major}.${minimalVersion.minor}.0`;
}

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
`The template uses an unsupported version of the ${chalk.greenBright('jfmengels/elm-review')} Elm package. It is using version ${version}, but I need it to be ${supportedRange}.

Please inform the template author and kindly ask them to update their configuration, or make a pull request to help them out.`
        /* eslint-enable prettier/prettier */
    );
  }
  const dirPath = PathHelpers.format(path.dirname(elmJsonPath));

  throw new ErrorMessage.CustomError(
    /* eslint-disable prettier/prettier */
'UNSUPPORTED ELM-REVIEW VERSION',
`You are using an unsupported version of the ${chalk.greenBright('jfmengels/elm-review')} Elm package.
You are using version ${chalk.red(version)}, but I need it to be ${chalk.greenBright(supportedRange)}.

Please upgrade your version by running the following commands:
${chalk.magenta(`
cd ${dirPath}
npx elm-json install jfmengels/elm-review@${minimalVersion.major}
`)}
If that doesn't work, try out:
${chalk.magenta(`
cd ${dirPath}
npx elm-json upgrade --unsafe`)}`
      /* eslint-enable prettier/prettier */
  );
}

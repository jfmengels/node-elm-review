const Anonymize = require('../lib/anonymize');

/**
 * Convert Windows output to UNIX output.
 *
 * @param {string} output
 * @param {boolean} [anonymizeVersion=true]
 * @returns {string}
 */
function normalize(output, anonymizeVersion = true) {
  const normalizedOutput = output.replace(
    // Windows has different error codes.
    "Error: EPERM: operation not permitted, open '<local-path>\\test\\project-with-suppressed-errors-no-write\\review\\suppressed\\NoUnused.Variables.json'",
    "Error: EACCES: permission denied, open '<local-path>/test/project-with-suppressed-errors-no-write/review/suppressed/NoUnused.Variables.json'"
  );

  return (
    Anonymize.paths(
      anonymizeVersion
        ? Anonymize.pathsAndVersions(normalizedOutput, true)
        : normalizedOutput,
      true
    )
      // Prompts uses different characters on Windows.
      .replace(/√/g, '✔')
      // eslint-disable-next-line unicorn/better-regex -- Matching a literal pattern.
      .replace(/\.\.\./g, '…')
  );
}

module.exports = {
  normalize
};

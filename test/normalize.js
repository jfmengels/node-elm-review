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
      .replace(
        // eslint-disable-next-line no-control-regex -- Uh huh. And? (Matches literal escape characters.)
        /\u001B\[22m \u001B\[90m...\u001B\[39m yes/g,
        '\u001B[22m \u001B[90m…\u001B[39m yes'
      )
      .replace(/»/g, '›')
  );
}

module.exports = {
  normalize
};

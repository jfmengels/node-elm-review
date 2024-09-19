/**
 * @template {string} G
 * @template {string} N
 * @param {G} group
 * @param {N} name
 * @returns {`test/snapshots/${G}/${N}.txt`}
 */
function snapshotPath(group, name) {
  return `test/snapshots/${group}/${name}.txt`;
}

module.exports = {
  snapshotPath
};

/**
 * A "major.minor.patch" version string, e.g. `1.0.0`.
 */
export type VersionString = `${number}.${number}.${number}`;

/**
 * A dependency support version, e.g. `1.0.0 <= v < 2.0.0`.
 */
export type VersionRange = `${VersionString} <= v < ${VersionString}`;

/**
 * @import {Dependencies, ElmJson, ApplicationElmJson, PackageElmJson, PackageName, ApplicationDependencyList} from './types/content';
 * @import {Options} from './types/options';
 * @import {VersionString} from './types/version';
 */

const ProjectJsonFiles = require('./project-json-files');
const TemplateDependencies = require('./template-dependencies');

/**
 * @param {ApplicationElmJson} elmJson
 * @returns {ApplicationDependencyList}
 */
function dependenciesForApplication(elmJson) {
  return {
    ...elmJson['test-dependencies'].direct,
    ...elmJson['test-dependencies'].indirect,
    ...elmJson.dependencies.direct,
    ...elmJson.dependencies.indirect
  };
}

/**
 * @param {Options} options
 * @param {string} rawElmJson
 * @param {PackageElmJson} elmJson
 * @param {VersionString} elmVersion
 * @returns {ApplicationDependencyList}
 */
function dependenciesForPackage(options, rawElmJson, elmJson, elmVersion) {
  const {direct, indirect} = TemplateDependencies.solve(
    options,
    elmVersion,
    rawElmJson,
    elmJson['test-dependencies'],
    false
  );
  return {...direct, ...indirect};
}

/**
 * @param {Options} options
 * @param {string} rawElmJson
 * @param {ElmJson} elmJson
 * @param {VersionString} elmVersion
 * @returns {Promise<Dependencies>}
 */
async function collect(options, rawElmJson, elmJson, elmVersion) {
  const dependenciesEntries =
    elmJson.type === 'application'
      ? dependenciesForApplication(elmJson)
      : dependenciesForPackage(options, rawElmJson, elmJson, elmVersion);

  // Mutated in the computation of `projectDepsPromises` below
  let hasDependenciesThatCouldNotBeDownloaded = false;

  const projectDepsPromises = Object.entries(dependenciesEntries).map(
    async ([pkgName, packageVersion]) => {
      const name = /** @type {PackageName} */ (pkgName);

      const [docsJson, dependencyElmJson] = await Promise.all([
        ProjectJsonFiles.getDocsJson(
          options,
          elmVersion,
          name,
          packageVersion
        ).catch(() => {
          hasDependenciesThatCouldNotBeDownloaded = true;
          return [];
        }),
        ProjectJsonFiles.getElmJson(
          options,
          elmVersion,
          name,
          packageVersion
        ).catch(() => {
          hasDependenciesThatCouldNotBeDownloaded = true;
          return defaultElmJson(name, packageVersion);
        })
      ]);

      return {
        name,
        docsJson,
        elmJson: dependencyElmJson
      };
    }
  );

  const projectDeps = await Promise.all(projectDepsPromises);

  if (hasDependenciesThatCouldNotBeDownloaded && options.report !== 'json') {
    console.log(
      `
I could not fetch all the data I need about your project’s dependencies. Please
connect to the Internet so I can download and cache the data for future uses.
I will try to review the project anyway, but you might get unexpected results…
`.trim(),
      '\n'
    );
  }

  return projectDeps;
}

/**
 * @param {PackageName} name
 * @param {VersionString} packageVersion
 * @returns {PackageElmJson}
 */
function defaultElmJson(name, packageVersion) {
  return {
    type: 'package',
    name,
    summary:
      'Analyzes Elm projects, to help find mistakes before your users find them.',
    license: 'BSD-3-Clause',
    version: packageVersion,
    'exposed-modules': [],
    'elm-version': '0.19.0 <= v < 0.20.0',
    dependencies: {
      'elm/core': '1.0.2 <= v < 2.0.0'
    },
    'test-dependencies': {}
  };
}

module.exports = {
  collect
};

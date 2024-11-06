/**
 * @import {ApplicationDependencyList, PackageElmJson, PackageName} from './types/content';
 * @import {VersionString} from './types/version';
 */

const ProjectJsonFiles = require('./project-json-files');

/**
 * @param {ApplicationDependencyList} reviewDirectDependencies
 * @param {VersionString} elmVersion
 * @returns {Promise<Record<string, string>>}
 */
async function collectRuleLinks(reviewDirectDependencies, elmVersion) {
  const elmJsonForReviewDependenciesPromises = Object.entries(
    reviewDirectDependencies
  )
    .filter(([name]) => !name.startsWith('elm/'))
    .map(
      async ([name, packageVersion]) =>
        await ProjectJsonFiles.getElmJsonFromElmHome(
          elmVersion,
          name,
          packageVersion
        ).catch(() => null)
    );

  const elmJsonForReviewDependencies = await Promise.all(
    elmJsonForReviewDependenciesPromises
  ).then((items) => items.filter((item) => item !== null));

  return computeLinksToRuleDocs(
    reviewDirectDependencies,
    elmJsonForReviewDependencies
  );
}

/**
 * @param {ApplicationDependencyList} reviewDirectDependencies
 * @param {PackageElmJson[]} elmJsonForReviewDependencies
 * @returns {Record<string, string>}
 */
function computeLinksToRuleDocs(
  reviewDirectDependencies,
  elmJsonForReviewDependencies
) {
  return Object.entries(reviewDirectDependencies).reduce(
    (acc, [depName, packageVersion]) => {
      const dep = elmJsonForReviewDependencies.find(
        (elmJson) => elmJson.name === depName
      );

      if (!dep || !('jfmengels/elm-review' in dep.dependencies)) {
        return acc;
      }

      const exposedModules = Array.isArray(dep['exposed-modules'])
        ? dep['exposed-modules']
        : Object.values(dep['exposed-modules']).reduce((acc, items) => [
            ...acc,
            ...items
          ]);

      for (const moduleName of exposedModules) {
        acc[moduleName] = linkToModule(
          /** @type {PackageName} */ (depName),
          packageVersion,
          moduleName
        );
      }

      return acc;
    },
    /** @type {Record<string, string>} */ ({})
  );
}

/**
 * @param {PackageName} dependencyName
 * @param {VersionString} packageVersion
 * @param {string} moduleName
 * @returns {string}
 */
function linkToModule(dependencyName, packageVersion, moduleName) {
  const urlModuleName = moduleName.split('.').join('-');
  return `https://package.elm-lang.org/packages/${dependencyName}/${packageVersion}/${urlModuleName}`;
}

module.exports = {
  collectRuleLinks
};

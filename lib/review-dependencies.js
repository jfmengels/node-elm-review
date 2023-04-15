const ProjectJsonFiles = require('./project-json-files');

module.exports = {
  collectRuleLinks
};

async function collectRuleLinks(reviewDirectDependencies, elmVersion) {
  const elmJsonForReviewDependenciesPromises = Object.entries(
    reviewDirectDependencies
  )
    .filter(([name]) => !name.startsWith('elm/'))
    .map(([name, packageVersion]) =>
      ProjectJsonFiles.getElmJsonFromElmHome(
        elmVersion,
        name,
        packageVersion
      ).catch(() => null)
    );

  const elmJsonForReviewDependencies = await Promise.all(
    elmJsonForReviewDependenciesPromises
  ).then((items) => items.filter(Boolean));

  return computeLinksToRuleDocs(
    reviewDirectDependencies,
    elmJsonForReviewDependencies
  );
}

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
        : Object.values(dep['exposed-modules']).reduce((acc, items) =>
            acc.concat(items)
          );

      exposedModules.forEach((moduleName) => {
        acc[moduleName] = linkToModule(depName, packageVersion, moduleName);
      });
      return acc;
    },
    {}
  );
}

function linkToModule(dependencyName, packageVersion, moduleName) {
  const urlModuleName = moduleName.split('.').join('-');
  return `https://package.elm-lang.org/packages/${dependencyName}/${packageVersion}/${urlModuleName}`;
}

const path = require('path');
const os = require('os');
const ProjectJsonFiles = require('./project-json-files');

const elmRoot =
  process.env.ELM_HOME ||
  path.join(
    os.homedir(),
    os.platform() === 'win32' ? 'AppData/Roaming/elm' : '.elm'
  );

async function collect(options, elmJson, reviewDirectDependencies, elmVersion) {
  const dependenciesEntries =
    elmJson.type === 'application'
      ? {
          ...elmJson.dependencies.direct,
          ...elmJson.dependencies.indirect,
          ...elmJson['test-dependencies'].direct,
          ...elmJson['test-dependencies'].indirect
        }
      : {
          ...elmJson.dependencies,
          ...elmJson['test-dependencies']
        };

  const elmReviewDependencyCache = (name, packageVersion) =>
    path.join(
      elmRoot,
      'elm-review',
      options.packageJsonVersion,
      'packages',
      elmVersion,
      name,
      packageVersion
    );

  // Mutated in the computation of `projectDepsPromises` below
  let hasDependenciesThatCouldNotBeDownloaded = false;

  const projectDepsPromises = Object.entries(dependenciesEntries).map(
    async ([name, constraint]) => {
      const packageVersion = constraint.split(' ')[0];

      const [docsJson, dependencyElmJson] = await Promise.all([
        ProjectJsonFiles.getDocsJson(
          options,
          elmVersion,
          elmReviewDependencyCache(name, packageVersion),
          name,
          packageVersion
        ).catch(() => {
          hasDependenciesThatCouldNotBeDownloaded = true;
          return [];
        }),
        ProjectJsonFiles.getElmJson(
          options,
          elmVersion,
          elmReviewDependencyCache(name, packageVersion),
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

  const projectDeps = await Promise.all(projectDepsPromises).then((items) =>
    items.filter(Boolean)
  );

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
  collect,
  collectRuleLinks
};

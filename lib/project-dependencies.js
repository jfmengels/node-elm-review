const path = require('path');
const util = require('util');
const os = require('os');
const got = require('got');
const fs = require('fs-extra');

const fsMkdirp = util.promisify(fs.mkdirp);
const fsReadJson = util.promisify(fs.readJson);
const fsWriteJson = util.promisify(fs.writeJson);

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

  const elmRoot =
    process.env.ELM_HOME ||
    path.join(
      os.homedir(),
      os.platform() === 'win32' ? 'AppData/Roaming/elm' : '.elm'
    );

  const directory = (name, packageVersion) =>
    path.join(elmRoot, elmVersion, 'packages', name, packageVersion);

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
        getDocsJson(
          directory(name, packageVersion),
          elmReviewDependencyCache(name, packageVersion),
          name,
          packageVersion
        ).catch(() => {
          hasDependenciesThatCouldNotBeDownloaded = true;
          return [];
        }),
        getElmJson(
          directory(name, packageVersion),
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

  const elmJsonForReviewDependenciesPromises = Object.entries(
    reviewDirectDependencies
  )
    .filter(([name]) => !(name in dependenciesEntries))
    .map(([name, packageVersion]) =>
      getElmJson(
        directory(name, packageVersion),
        elmReviewDependencyCache(name, packageVersion),
        name,
        packageVersion
      ).catch(() => null)
    );

  const [projectDeps, elmJsonForReviewDependencies] = await Promise.all([
    Promise.all(projectDepsPromises).then((items) => items.filter(Boolean)),
    Promise.all(elmJsonForReviewDependenciesPromises).then((items) =>
      items.filter(Boolean)
    )
  ]);

  const linksToRuleDocs = computeLinksToRuleDocs(
    reviewDirectDependencies,
    projectDeps,
    elmJsonForReviewDependencies
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

  return {
    projectDeps,
    linksToRuleDocs
  };
}

function computeLinksToRuleDocs(
  reviewDirectDependencies,
  projectDeps,
  elmJsonForReviewDependencies
) {
  return Object.entries(reviewDirectDependencies).reduce(
    (acc, [depName, packageVersion]) => {
      let dep = projectDeps.find(
        (dep) => dep.elmJson && dep.elmJson.name === depName
      );

      if (dep) {
        dep = dep.elmJson;
      } else {
        dep = elmJsonForReviewDependencies.find(
          (elmJson) => elmJson.name === depName
        );
      }

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

function getDocsJson(
  directory,
  elmReviewDependencyCache,
  name,
  packageVersion
) {
  return fsReadJson(path.join(directory, 'docs.json'))
    .catch(() => fsReadJson(path.join(elmReviewDependencyCache, 'docs.json')))
    .catch(() =>
      readDocsJsonFromPackagesWebsite(name, packageVersion).then((result) => {
        cacheFile(
          elmReviewDependencyCache,
          'docs.json',
          result
        ).catch(() => {});
        return result;
      })
    );
}

function getElmJson(directory, elmReviewDependencyCache, name, packageVersion) {
  return fsReadJson(path.join(directory, 'elm.json'))
    .catch(() => fsReadJson(path.join(elmReviewDependencyCache, 'elm.json')))
    .catch(() =>
      readElmJsonFromPackagesWebsite(name, packageVersion).then((result) => {
        cacheFile(elmReviewDependencyCache, 'elm.json', result).catch(() => {});
        return result;
      })
    );
}

async function cacheFile(directory, name, jsonContent) {
  await fsMkdirp(directory).catch(() => {});
  return fsWriteJson(path.join(directory, name), jsonContent);
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

async function readDocsJsonFromPackagesWebsite(packageName, packageVersion) {
  const response = await got(
    `https://package.elm-lang.org/packages/${packageName}/${packageVersion}/docs.json`
  );
  return JSON.parse(response.body);
}

async function readElmJsonFromPackagesWebsite(packageName, packageVersion) {
  const response = await got(
    `https://package.elm-lang.org/packages/${packageName}/${packageVersion}/elm.json`
  );
  return JSON.parse(response.body);
}

module.exports = {
  collect
};

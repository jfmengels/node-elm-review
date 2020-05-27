const path = require('path');
const util = require('util');
const os = require('os');
const got = require('got');
const fs = require('fs-extra');

const fsMkdirp = util.promisify(fs.mkdirp);
const fsReadJson = util.promisify(fs.readJson);
const fsWriteJson = util.promisify(fs.writeJson);

async function collect(options, elmJson, elmVersion) {
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

  // Mutated in the promise below that gets the dependencies
  let hasDependenciesThatCouldNotBeDownloaded = false;

  const dependenciesInfo = await Promise.all(
    Object.entries(dependenciesEntries).map(async ([name, constraint]) => {
      const packageVersion = constraint.split(' ')[0];

      const elmRoot =
        process.env.ELM_HOME ||
        path.join(
          os.homedir(),
          os.platform() === 'win32' ? 'AppData/Roaming/elm' : '.elm'
        );
      const directory = path.join(
        elmRoot,
        elmVersion,
        'packages',
        name,
        packageVersion
      );
      const elmReviewDependencyCache = path.join(
        elmRoot,
        'elm-review',
        options.packageJsonVersion,
        'packages',
        elmVersion,
        name,
        packageVersion
      );

      const [docsJson, dependencyElmJson] = await Promise.all([
        getDocsJson(
          directory,
          elmReviewDependencyCache,
          name,
          packageVersion
        ).catch(() => {
          hasDependenciesThatCouldNotBeDownloaded = true;
          return [];
        }),
        getElmJson(
          directory,
          elmReviewDependencyCache,
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
    })
  );

  if (hasDependenciesThatCouldNotBeDownloaded && options.report !== 'json') {
    console.error(
      `
I could not fetch all the data I need about your project’s dependencies. Please
connect to the Internet so I can download and cache the data for future uses.
I will try to review the project anyway, but you might get unexpected results…
`.trim(),
      '\n'
    );
  }

  return dependenciesInfo;
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

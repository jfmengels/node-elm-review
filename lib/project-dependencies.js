const path = require('path');
const util = require('util');
const os = require('os');
const got = require('got');
const fs = require('fs-extra');

const fsReadJson = util.promisify(fs.readJson);

function collect(elmJson, elmVersion) {
  const dependencies =
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

  return Promise.all(
    Object.entries(dependencies).map(async ([name, constraint]) => {
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

      const [docsJson, dependencyElmJson] = await Promise.all([
        fsReadJson(path.join(directory, 'docs.json')).catch(() =>
          readDocsJsonFromPackagesWebsite(name, packageVersion)
        ),
        fsReadJson(path.join(directory, 'elm.json')).catch(() =>
          readElmJsonFromPackagesWebsite(name, packageVersion)
        )
      ]);

      return {
        name,
        docsJson,
        elmJson: dependencyElmJson
      };
    })
  );
}

async function readDocsJsonFromPackagesWebsite(packageName, packageVersion) {
  const response = await got(
    `https://package.elm-lang.org/packages/${packageName}/${packageVersion}/docs.json`
  );
  return response.body;
}

async function readElmJsonFromPackagesWebsite(packageName, packageVersion) {
  const response = await got(
    `https://package.elm-lang.org/packages/${packageName}/${packageVersion}/elm.json`
  );
  return response.body;
}

module.exports = {
  collect
};

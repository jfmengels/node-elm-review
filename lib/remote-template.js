const path = require('path');
const util = require('util');
const https = require('https');
const got = require('got');
const chalk = require('chalk');
const fs = require('fs-extra');
const Debug = require('./debug');
const MinVersion = require('./min-version');
const ErrorMessage = require('./error-message');
const TemplateDependencies = require('./template-dependencies');

module.exports = {
  getRelevantCommit,
  getRemoteElmJson,
  downloadSourceDirectories
};

const fsMkdirp = util.promisify(fs.mkdirp);
const fsWriteJson = util.promisify(fs.writeJson);

// GET LATEST INFORMATION ABOUT REPOSITORY

function getRelevantCommit(options, template) {
  return template.reference
    ? getLatestCommitForReference(options, template, template.reference)
    : findDefaultBranch(options, template).then((defaultBranch) => {
        Debug.log(`Default branch is: ${defaultBranch}`);
        return getLatestCommitForReference(options, template, defaultBranch);
      });
}

async function findDefaultBranch(options, template) {
  Debug.log('Fetching default branch');
  return makeGitHubApiRequest(
    options,
    `https://api.github.com/repos/${template.repoName}`,
    () => repoNotFoundErrorMessage(template.repoName)
  ).then((body) => body.default_branch);
}

function getLatestCommitForReference(options, template, reference) {
  Debug.log(`Fetching commit ${reference}`);
  return makeGitHubApiRequest(
    options,
    `https://api.github.com/repos/${template.repoName}/commits/${reference}`,
    (responseBody) => {
      if (responseBody.message === 'Not Found') {
        // This error means that the repo itself was not found
        return repoNotFoundErrorMessage(template.repoName);
      }

      return commitNotFoundErrorMessage(template.repoName, reference);
    }
  ).then((body) => body.sha);
}

// DOWNLOAD THE ELM.JSON FILE

async function getRemoteElmJson(options, template, reviewElmJsonPath, commit) {
  if (fs.existsSync(reviewElmJsonPath)) {
    return fs.readJsonSync(reviewElmJsonPath);
  }

  const elmJson = await downloadTemplateElmJson(options, template, commit);
  if (
    elmJson.dependencies &&
    elmJson.dependencies.direct &&
    elmJson.dependencies.direct['jfmengels/elm-review']
  ) {
    elmJson.dependencies.direct[
      'jfmengels/elm-review'
    ] = MinVersion.updateToAtLeastMinimalVersion(
      elmJson.dependencies.direct['jfmengels/elm-review']
    );
  }

  await fsMkdirp(path.dirname(reviewElmJsonPath));
  await fsWriteJson(reviewElmJsonPath, elmJson, {spaces: 4});
  return TemplateDependencies.update(options, reviewElmJsonPath);
}

async function downloadTemplateElmJson(options, template, commit) {
  const {repoName, pathToFolder} = template;
  const pathToFolderAsUrl = pathToFolder ? `/${pathToFolder}` : '';

  return got(
    `https://raw.githubusercontent.com/${repoName}/${commit}${pathToFolderAsUrl}/elm.json`
  )
    .catch((error) => {
      if (error.name === 'HTTPError' && error.response.statusCode === 404) {
        const pathToElmJson = pathToFolder
          ? `${pathToFolder.slice(1)}/elm.json`
          : 'elm.json';

        throw new ErrorMessage.CustomError(
          'TEMPLATE ELM.JSON NOT FOUND',
          /* eslint-disable prettier/prettier */
      `I found the ${chalk.yellow(repoName)} repository on GitHub,
but I could not find a ${chalk.yellow(pathToElmJson)} file in it.

I need this file to determine the rest of the configuration.`
          /* eslint-enable prettier/prettier */
        );
      }

      throw error;
    })
    .then((response) => {
      try {
        return JSON.parse(response.body);
      } catch (error) {
        throw new ErrorMessage.CustomError(
          'TEMPLATE ELM.JSON PARSING ERROR',
          /* eslint-disable prettier/prettier */
      `I found the ${chalk.yellow("elm.json")} associated with ${chalk.yellow(repoName)} repository on GitHub,
but I encountered a problem when parsing it:

${error.message}`
          /* eslint-enable prettier/prettier */
        );
      }
    });
}

const rateLimitErrorMessage = [
  'GITHUB RATE LIMIT EXCEEDED',
  `It looks like you exceeded the GitHub rate limit by using "--template" too many
times, this will likely last for 30 minutes.

In the meantime, you can use \`--github-auth your-github-username:your-api-token\`.
Follow this guide: https://docs.github.com/en/github/authenticating-to-github/creating-a-personal-access-token to create an API token, and give it access to public repositories.

To avoid this problem and to make the review process faster, consider setting up
elm-review in your project:

    elm-review init
    elm-review init --template <some-configuration>`
];

function repoNotFoundErrorMessage(repoName) {
  return [
    'REPOSITORY NOT FOUND',
    /* eslint-disable prettier/prettier */
  `I could not find the ${chalk.yellow(repoName)} repository on GitHub.
Check the spelling and make sure it is a public repository, as I can't work
with private ones at the moment.`
    /* eslint-enable prettier/prettier */
  ];
}

function commitNotFoundErrorMessage(repoName, reference) {
  return [
    'BRANCH OR COMMIT NOT FOUND',
    /* eslint-disable prettier/prettier */
  `I found the ${chalk.yellow(repoName)} repository on GitHub,
but I could not find the branch or commit ${chalk.yellow(reference)}.
Check the spelling and make sure it has been pushed.`
    /* eslint-enable prettier/prettier */
  ];
}

// DOWNLOAD TEMPLATE FILES

function downloadSourceDirectories(
  options,
  template,
  commit,
  buildFolder,
  reviewElmJson
) {
  return Promise.all(
    reviewElmJson['source-directories'].map((sourceDirectory) =>
      downloadDirectory(options, template, commit, buildFolder, sourceDirectory)
    )
  );
}

async function downloadDirectory(
  options,
  template,
  commit,
  basePath,
  directory
) {
  const {repoName, pathToFolder = ''} = template;
  const destinationDirectory = directory.split('..').join('parent');

  await fsMkdirp(path.join(basePath, destinationDirectory));
  const fileListing = await makeGitHubApiRequest(
    options,
    `https://api.github.com/repos/${repoName}/contents${pathToFolder}/${directory}?ref=${commit}`
      .split('//')
      .join('/')
  );

  await Promise.all(
    fileListing.map((fileOrDir) => {
      if (fileOrDir.type === 'file') {
        if (options.subcommand !== 'init' && !fileOrDir.name.endsWith('.elm')) {
          return Promise.resolve();
        }

        return downloadFile(
          fileOrDir.download_url,
          path.join(basePath, destinationDirectory, fileOrDir.name)
        );
      }

      return downloadDirectory(
        options,
        template,
        commit,
        basePath,
        path.join(directory, fileOrDir.name)
      );
    })
  );
}

function downloadFile(url, dest) {
  return new Promise((resolve) => {
    const file = fs.createWriteStream(dest);
    https.get(url, function (response) {
      response.pipe(file);
      file.on('finish', function () {
        file.close(resolve);
      });
    });
  });
}

function makeGitHubApiRequest(options, url, handleNotFound) {
  const parameters = {responseType: 'json'};
  if (options.gitHubUser && options.gitHubPassword) {
    parameters.user = options.gitHubUser;
    parameters.password = options.gitHubPassword;
  }

  Debug.log(`Making API request to GitHub: ${url}`);
  return got(url, parameters)
    .then((response) => response.body)
    .catch((error) => {
      Debug.log(`An error occurred when making a request to the GitHub API:`);
      Debug.log(`# url: ${url}`);
      Debug.log(`# statusCode: ${error.response.statusCode}`);
      Debug.log(`# body:\n${JSON.stringify(error.response.body, 0, 4)}`);
      if (error.name === 'HTTPError') {
        switch (error.response.statusCode) {
          case 403:
            throw new ErrorMessage.CustomError(...rateLimitErrorMessage);

          case 404:
          case 422: {
            if (handleNotFound) {
              throw new ErrorMessage.CustomError(
                ...handleNotFound(error.response.body)
              );
            }

            throw error;
          }

          default:
            throw error;
        }
      }

      throw error;
    });
}

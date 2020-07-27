const path = require('path');
const util = require('util');
const https = require('https');
const got = require('got');
const chalk = require('chalk');
const fs = require('fs-extra');
const errorMessage = require('./error-message');
const Debug = require('./debug');

module.exports = {
  getRelevantCommit,
  getRemoteElmJson,
  downloadSourceDirectories
};

const fsMkdirp = util.promisify(fs.mkdirp);
const fsWriteFile = util.promisify(fs.writeFile);

// GET LATEST INFORMATION ABOUT REPOSITORY

function getRelevantCommit(options) {
  return options.template.reference
    ? getLatestCommitForReference(options, options.template.reference)
    : findDefaultBranch(options).then((defaultBranch) => {
        Debug.log(`Default branch is: ${defaultBranch}`);
        return getLatestCommitForReference(options, defaultBranch);
      });
}

async function findDefaultBranch(options) {
  Debug.log('Fetching default branch');
  const {repoName} = options.template;
  return makeGitHubApiRequest(
    options,
    `https://api.github.com/repos/${repoName}`,
    () => repoNotFoundErrorMessage(repoName)
  ).then((body) => body.default_branch);
}

function getLatestCommitForReference(options, reference) {
  Debug.log(`Fetching commit ${reference}`);
  const {repoName} = options.template;
  return makeGitHubApiRequest(
    options,
    `https://api.github.com/repos/${repoName}/commits/${reference}`,
    (responseBody) => {
      if (responseBody.message === 'Not Found') {
        // This error means that the repo itself was not found
        return repoNotFoundErrorMessage(repoName);
      }

      return commitNotFoundErrorMessage(repoName, reference);
    }
  ).then((body) => body.sha);
}

// DOWNLOAD THE ELM.JSON FILE

async function getRemoteElmJson(options, commit) {
  const reviewElmJsonPath = options.pathToTemplateElmJson(commit);
  if (fs.existsSync(reviewElmJsonPath)) {
    return fs.readJsonSync(reviewElmJsonPath);
  }

  const rawElmJson = await downloadTemplateElmJson(options, commit);

  await fsMkdirp(path.dirname(reviewElmJsonPath));
  await fsWriteFile(reviewElmJsonPath, rawElmJson);
  return JSON.parse(rawElmJson);
}

async function downloadTemplateElmJson(options, commit) {
  const {repoName, pathToFolder} = options.template;
  const pathToFolderAsUrl = pathToFolder ? `/${pathToFolder}` : '';

  return got(
    `https://raw.githubusercontent.com/${repoName}/${commit}${pathToFolderAsUrl}/elm.json`
  )
    .catch((error) => {
      if (error.name === 'HTTPError' && error.response.statusCode === 404) {
        const pathToElmJson = pathToFolder
          ? `${pathToFolder.slice(1)}/elm.json`
          : 'elm.json';

        throw new errorMessage.CustomError(
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
    .then((response) => response.body);
}

const rateLimitErrorMessage = [
  'GITHUB RATE LIMIT EXCEEDED',
  `It looks like you exceeded the GitHub rate limit by calling this command too
many times. Let the author know that this happened to you.

In the meantime, you can use \`--github-auth your-github-username:your-api-token\`.
Follow this guide: https://docs.github.com/en/github/authenticating-to-github/creating-a-personal-access-token to create an API token, and give it access to public repositories.`
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
  commit,
  buildFolder,
  reviewElmJson
) {
  return Promise.all(
    reviewElmJson['source-directories'].map((sourceDirectory) =>
      downloadDirectory(options, commit, buildFolder, sourceDirectory)
    )
  );
}

async function downloadDirectory(options, commit, basePath, directory) {
  const {repoName, pathToFolder = ''} = options.template;

  await fsMkdirp(path.join(basePath, directory));
  const fileListing = await makeGitHubApiRequest(
    options,
    `https://api.github.com/repos/${repoName}/contents${pathToFolder}/${directory}?ref=${commit}`
      .split('//')
      .join('/')
  );

  await Promise.all(
    fileListing.map((fileOrDir) => {
      if (fileOrDir.type === 'file') {
        if (!fileOrDir.name.endsWith('.elm')) {
          return Promise.resolve();
        }

        return downloadFile(
          fileOrDir.download_url,
          path.join(basePath, directory, fileOrDir.name)
        );
      }

      return downloadDirectory(
        options,
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
            throw new errorMessage.CustomError(...rateLimitErrorMessage);

          case 404:
          case 422: {
            if (handleNotFound) {
              throw new errorMessage.CustomError(
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

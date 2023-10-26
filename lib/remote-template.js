const fs = require('fs');
const path = require('path');
const https = require('https');
const {default: got} = require('got');
const chalk = require('chalk');
const Debug = require('./debug');
const FS = require('./fs-wrapper');
const MinVersion = require('./min-version');
const ErrorMessage = require('./error-message');
const TemplateDependencies = require('./template-dependencies');

/**
 * @typedef { import("got").OptionsOfJSONResponseBody } OptionsOfJSONResponseBody
 * @typedef { import("./types/options").Options } Options
 * @typedef { import("./types/options").Template } Template
 * @typedef { import("./types/content").ApplicationElmJson } ApplicationElmJson
 * @typedef { import("./types/path").Path } Path
 */

module.exports = {
  getRelevantCommit,
  getRemoteElmJson,
  downloadSourceDirectories
};

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

/**
 * Download the elm.json file.
 * @param {Options} options
 * @param {Template} template
 * @param {Path} reviewElmJsonPath
 * @param {string} commit
 * @param {boolean} forInit
 * @returns {Promise<ApplicationElmJson>}
 */
async function getRemoteElmJson(
  options,
  template,
  reviewElmJsonPath,
  commit,
  forInit
) {
  if (!forInit && fs.existsSync(reviewElmJsonPath)) {
    return FS.readJsonFileSync(reviewElmJsonPath);
  }

  const elmJson = await downloadTemplateElmJson(template, commit);

  if (
    elmJson.dependencies &&
    elmJson.dependencies.direct &&
    elmJson.dependencies.direct['jfmengels/elm-review']
  ) {
    const packageVersion = elmJson.dependencies.direct['jfmengels/elm-review'];
    const [major] = packageVersion.split('.');

    if (Number.parseInt(major, 10) !== MinVersion.minimalVersion.major) {
      // Major version for which the configuration exists is not compatible
      MinVersion.validate(options, reviewElmJsonPath, packageVersion);
    }

    elmJson.dependencies.direct['jfmengels/elm-review'] =
      MinVersion.updateToAtLeastMinimalVersion(packageVersion);
  }

  return TemplateDependencies.update(options, elmJson);
}

async function downloadTemplateElmJson(template, commit) {
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
          // prettier-ignore
          'TEMPLATE ELM.JSON NOT FOUND',
          // prettier-ignore
          `I found the ${chalk.yellow(repoName)} repository on GitHub,
but I could not find a ${chalk.yellow(pathToElmJson)} file in it.

I need this file to determine the rest of the configuration.`
        );
      }

      throw error;
    })
    .then((response) => {
      try {
        return JSON.parse(response.body);
      } catch (error) {
        throw new ErrorMessage.CustomError(
          // prettier-ignore
          'TEMPLATE ELM.JSON PARSING ERROR',
          // prettier-ignore
          `I found the ${chalk.yellow("elm.json")} associated with ${chalk.yellow(repoName)} repository on GitHub,
but I encountered a problem when parsing it:

${error.message}`
        );
      }
    });
}

const rateLimitErrorMessage = {
  title: 'GITHUB RATE LIMIT EXCEEDED',
  message: `It looks like you exceeded the GitHub rate limit by using "--template" too many
times, this will likely last for 30 minutes.

In the meantime, you can use \`--github-auth your-github-username:your-api-token\`.
Follow this guide: https://docs.github.com/en/github/authenticating-to-github/creating-a-personal-access-token to create an API token, and give it access to public repositories.

To avoid this problem and to make the review process faster, consider setting up
elm-review in your project:

    elm-review init
    elm-review init --template <some-configuration>`
};

function repoNotFoundErrorMessage(repoName) {
  return {
    title: 'REPOSITORY NOT FOUND',
    message:
      // prettier-ignore
      `I could not find the ${chalk.yellow(repoName)} repository on GitHub.
Check the spelling and make sure it is a public repository, as I can't work
with private ones at the moment.`
  };
}

function commitNotFoundErrorMessage(repoName, reference) {
  return {
    title: 'BRANCH OR COMMIT NOT FOUND',
    message:
      // prettier-ignore
      `I found the ${chalk.yellow(repoName)} repository on GitHub,
but I could not find the branch or commit ${chalk.yellow(reference)}.
Check the spelling and make sure it has been pushed.`
  };
}

// DOWNLOAD TEMPLATE FILES

function downloadSourceDirectories(
  options,
  template,
  commit,
  basePath,
  reviewElmJson
) {
  return Promise.all(
    reviewElmJson['source-directories'].map((sourceDirectory) =>
      downloadDirectory(options, template, commit, basePath, sourceDirectory)
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

  await FS.mkdirp(path.join(basePath, destinationDirectory));
  const fileListing = await makeGitHubApiRequest(
    options,
    `https://api.github.com/repos/${repoName}/contents${pathToFolder}/${directory}?ref=${commit}`
      .split('//')
      .join('/')
  );

  await Promise.all(
    fileListing.map((fileOrDir) => {
      if (fileOrDir.type === 'file') {
        if (options.subcommand === 'init' || fileOrDir.name.endsWith('.elm')) {
          return downloadFile(
            fileOrDir.download_url,
            path.join(basePath, destinationDirectory, fileOrDir.name)
          );
        }

        return Promise.resolve();
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
    https.get(url, (response) => {
      response.pipe(file);
      file.on('finish', () => {
        file.close(resolve);
      });
    });
  });
}

/**
 * @typedef {{message: string}} JsonResponse
 */

/**
 * Make a request to the GitHub API.
 * @param {Options} options
 * @param {string} url
 * @param {((arg: JsonResponse) => {title: string, message: string})} [handleNotFound]
 * @returns {Promise<object>}
 */
function makeGitHubApiRequest(options, url, handleNotFound) {
  /** @type {OptionsOfJSONResponseBody}} */
  const parameters = {responseType: 'json'};
  if (options.gitHubUser && options.gitHubPassword) {
    parameters.username = options.gitHubUser;
    parameters.password = options.gitHubPassword;
  }

  Debug.log(`Making API request to GitHub: ${url}`);
  return got(url, parameters)
    .then((response) => response.body)
    .catch((error) => {
      Debug.log(`An error occurred when making a request to the GitHub API:`);
      Debug.log(`# url: ${url}`);
      Debug.log(`# statusCode: ${error.response.statusCode}`);
      Debug.log(`# body:\n${JSON.stringify(error.response.body, null, 4)}`);
      if (error.name === 'HTTPError') {
        switch (error.response.statusCode) {
          case 403:
            throw new ErrorMessage.CustomError(
              rateLimitErrorMessage.title,
              rateLimitErrorMessage.message
            );

          case 404:
          case 422: {
            if (handleNotFound) {
              const {title, message} = handleNotFound(error.response.body);
              throw new ErrorMessage.CustomError(title, message);
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

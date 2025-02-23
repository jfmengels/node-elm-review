/**
 * @import {OptionsOfJSONResponseBody} from 'got';
 * @import {ErrorMessageInfo} from './types/error-message';
 * @import {Options, Template} from './types/options';
 * @import {ElmJson, ApplicationElmJson} from './types/content';
 * @import {Path} from './types/path';
 */
const https = require('node:https');
const path = require('pathe');
const chalk = require('chalk');
const fs = require('graceful-fs');
const got = require('got').default;
const Debug = require('./debug');
const ErrorMessage = require('./error-message');
const FS = require('./fs-wrapper');
const MinVersion = require('./min-version');
const TemplateDependencies = require('./template-dependencies');

// GET LATEST INFORMATION ABOUT REPOSITORY

/**
 * @param {Options} options
 * @param {Template} template
 * @returns {Promise<string>}
 */
async function getRelevantCommit(options, template) {
  if (template.reference) {
    return await getLatestCommitForReference(
      options,
      template,
      template.reference
    );
  }

  const defaultBranch = await findDefaultBranch(options, template);
  Debug.log(`Default branch is: ${defaultBranch}`, options.debug);
  return await getLatestCommitForReference(options, template, defaultBranch);
}

/**
 * @returns {Promise<string>}
 * @param {Options} options
 * @param {Template} template
 */
async function findDefaultBranch(options, template) {
  Debug.log('Fetching default branch', options.debug);
  const body = /** @type {{default_branch: string}} */ (
    await makeGitHubApiRequest(
      options,
      `https://api.github.com/repos/${template.repoName}`,
      () => repoNotFoundErrorMessage(template.repoName)
    )
  );
  return body.default_branch;
}

/**
 * @returns {Promise<string>}
 * @param {Options} options
 * @param {Template} template
 * @param {string} reference
 */
async function getLatestCommitForReference(options, template, reference) {
  Debug.log(`Fetching commit ${reference}`, options.debug);
  const body = /** @type {{sha: string}} */ (
    await makeGitHubApiRequest(
      options,
      `https://api.github.com/repos/${template.repoName}/commits/${reference}`,
      (responseBody) => {
        if (responseBody.message === 'Not Found') {
          // This error means that the repo itself was not found
          return repoNotFoundErrorMessage(template.repoName);
        }

        return commitNotFoundErrorMessage(template.repoName, reference);
      }
    )
  );
  return body.sha;
}

/**
 * Download the elm.json file.
 *
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
    return /** @type {ApplicationElmJson} */ (
      FS.readJsonFileSync(reviewElmJsonPath)
    );
  }

  const elmJson = await downloadTemplateElmJson(template, commit);

  if (elmJson.dependencies?.direct?.['jfmengels/elm-review']) {
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

/**
 * @param {Template} template
 * @param {string} commit
 * @returns {Promise<ApplicationElmJson>}
 */
async function downloadTemplateElmJson(template, commit) {
  const {repoName, pathToFolder} = template;
  const pathToFolderAsUrl = pathToFolder ? `/${pathToFolder}` : '';

  // TODO(@lishaduck) [engine:node@>=21]: We can use `fetch` now.
  const response = await got(
    `https://raw.githubusercontent.com/${repoName}/${commit}${pathToFolderAsUrl}/elm.json`
  ).catch((error) => {
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
  });

  const elmJson = parseElmJson(response.body, repoName);

  if (elmJson.type === 'package') {
    const referenceAsUrl = template.reference ? `/${template.reference}` : '';

    throw new ErrorMessage.CustomError(
      // prettier-ignore
      'INVALID TEMPLATE ELM.JSON TYPE',
      // prettier-ignore
      `I found the ${chalk.yellow('elm.json')} associated with ${chalk.yellow(repoName)} repository on GitHub,
but it is of type ${chalk.red('package')} when I need it to be of type ${chalk.yellow('application')}.

Maybe you meant to target the ${chalk.cyan('example')} or the ${chalk.cyan('preview')} folder in that repository?

    elm-review --template ${repoName}${referenceAsUrl}/example
    elm-review --template ${repoName}${referenceAsUrl}/review`
    );
  }

  return elmJson;
}

/**
 * @param {string} body
 * @param {string} repoName
 * @returns {ElmJson}
 */
function parseElmJson(body, repoName) {
  try {
    const json = /** @type {unknown} */ (JSON.parse(body));

    return /** @type {ElmJson} */ (json);
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
}

/**
 * @param {boolean} hasPat
 * @param {string} resetTime
 * @returns {ErrorMessageInfo}
 */
function rateLimitErrorMessage(hasPat, resetTime) {
  const patAdvice = hasPat
    ? ''
    : `In the meantime, you can use \`--github-auth=your-api-token\`.
Follow this guide: https://docs.github.com/en/github/authenticating-to-github/creating-a-personal-access-token to create an API token, and give it access to public repositories.`;

  return {
    title: 'GITHUB RATE LIMIT EXCEEDED',
    message: `It looks like you exceeded the GitHub rate limit by using "--template" too many
times, this will likely last until ${resetTime}.
${patAdvice}
To avoid this problem and to make the review process faster, consider setting up
elm-review in your project:

    elm-review init
    elm-review init --template <some-configuration>`
  };
}

/**
 * @param {string} repoName
 * @returns {ErrorMessageInfo}
 */
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

/**
 * @param {string} repoName
 * @param {string} reference
 * @returns {ErrorMessageInfo}
 */
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

/**
 * @param {Options} options
 * @param {Template} template
 * @param {string} commit
 * @param {string} basePath
 * @param {ApplicationElmJson} reviewElmJson
 * @returns {Promise<void>}
 */
async function downloadSourceDirectories(
  options,
  template,
  commit,
  basePath,
  reviewElmJson
) {
  await Promise.all(
    reviewElmJson['source-directories'].map(async (sourceDirectory) => {
      await downloadDirectory(
        options,
        template,
        commit,
        basePath,
        sourceDirectory
      );
    })
  );
}

/**
 * @param {Options} options
 * @param {Template} template
 * @param {string} commit
 * @param {string} basePath
 * @param {string} directory
 * @returns {Promise<void>}
 */
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
  const fileListing =
    /** @type {({ type: string; name: string; download_url: string; })[]} */ (
      await makeGitHubApiRequest(
        options,
        `https://api.github.com/repos/${repoName}/contents/${pathToFolder}/${directory}?ref=${commit}`
          .split('//')
          .join('/')
      )
    );

  await Promise.all(
    fileListing.map(async (fileOrDir) => {
      if (fileOrDir.type === 'file') {
        if (options.subcommand === 'init' || fileOrDir.name.endsWith('.elm')) {
          return await downloadFile(
            fileOrDir.download_url,
            path.join(basePath, destinationDirectory, fileOrDir.name)
          );
        }

        await Promise.resolve();
        return;
      }

      await downloadDirectory(
        options,
        template,
        commit,
        basePath,
        path.join(directory, fileOrDir.name)
      );
    })
  );
}

/**
 * Download a file to a destination.
 *
 * Returns a promise that resolves to null if the download was successful, or an error if it failed.
 *
 * @param {string} url
 * @param {Path} dest
 * @returns {Promise<NodeJS.ErrnoException | null | undefined>}
 */
async function downloadFile(url, dest) {
  return await new Promise((resolve) => {
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
 * Make a request to the GitHub API.
 *
 * @param {Options} options
 * @param {string} url
 * @param {((errorBody: {message: string}) => ErrorMessageInfo)} [handleNotFound]
 * @returns {Promise<unknown>}
 */
async function makeGitHubApiRequest(options, url, handleNotFound) {
  /** @type {OptionsOfJSONResponseBody} */
  const parameters = {
    responseType: 'json',
    headers: {
      Authorization: options.gitHubPat && `BEARER ${options.gitHubPat}`,
      'X-GitHub-Api-Version': '2022-11-28'
    }
  };

  Debug.log(`Making API request to GitHub: ${url}`, options.debug);
  try {
    // TODO(@lishaduck) [engine:node@>=21]: We can use `fetch` now.
    const response = await got(url, parameters);

    /** @type {{body: unknown}} */
    const {body} = response;

    return body;
  } catch (error) {
    Debug.log(
      `An error occurred when making a request to the GitHub API:`,
      options.debug
    );
    Debug.log(`# url: ${url}`, options.debug);
    Debug.log(`# statusCode: ${error.response.statusCode}`, options.debug);
    Debug.log(
      `# body:\n${JSON.stringify(error.response.body, null, 4)}`,
      options.debug
    );
    if (error.name === 'HTTPError') {
      switch (error.response.statusCode) {
        case 429:
        case 403: {
          const hasPat = options.gitHubPat !== undefined;
          const rateLimitReset = error.response.headers['x-ratelimit-reset'];
          const resetTime = new Date(rateLimitReset * 1000).toLocaleString();
          const {title, message} = rateLimitErrorMessage(hasPat, resetTime);

          throw new ErrorMessage.CustomError(title, message);
        }

        case 401: {
          throw new ErrorMessage.CustomError(
            'INVALID GITHUB CREDENTIALS',
            `It looks like the credentials that were provided using \`--github-auth\` were incorrect.

Please check that the credentials were correctly entered and that they are still valid.`
          );
        }

        case 404:
        case 422: {
          if (handleNotFound) {
            const {title, message} = handleNotFound(error.response.body);
            throw new ErrorMessage.CustomError(title, message);
          }

          throw error;
        }

        default: {
          throw error;
        }
      }
    }

    throw error;
  }
}

module.exports = {
  getRelevantCommit,
  getRemoteElmJson,
  downloadSourceDirectories
};

const path = require('path');
const util = require('util');
const https = require('https');
const crypto = require('crypto');
const got = require('got');
const temp = require('temp');
const chalk = require('chalk');
const fs = require('fs-extra');
const wrap = require('wrap-ansi');
const {hashElement} = require('folder-hash');
const elmCompiler = require('../vendor/node-elm-compiler');
const {getElmBinary} = require('./elm-binary');
const templateDependencies = require('./template-dependencies');
const errorMessage = require('./error-message');
const Debug = require('./debug');
const Anonymize = require('./anonymize');

const fsMkdirp = util.promisify(fs.mkdirp);
const fsEnsureDir = util.promisify(fs.ensureDir);
const fsReadJson = util.promisify(fs.readJson);
const fsWriteFile = util.promisify(fs.writeFile);

const templateSrc = path.join(__dirname, '../template/src');

async function cachedBuild(options, userSrc, reviewElmJsonPath, reviewElmJson) {
  const sourceDirectoriesHashes = reviewElmJson['source-directories'].map(
    (directory) =>
      hashElement(path.resolve(userSrc, directory), {
        folders: {exclude: ['.*', 'elm-stuff']},
        files: {include: ['*.elm']},
        algo: 'md5'
      })
  );
  const reviewElmJsonHash = hashElement(reviewElmJsonPath, {algo: 'md5'});

  const localElmReviewSourceHashes = options.localElmReviewSrc
    ? [
        hashElement(path.resolve(userSrc, options.localElmReviewSrc), {
          folders: {exclude: ['.*', 'elm-stuff']},
          files: {include: ['*.elm']},
          algo: 'md5'
        })
      ]
    : [];

  const hashes = await Promise.all([
    ...sourceDirectoriesHashes,
    ...localElmReviewSourceHashes,
    reviewElmJsonHash
  ]);

  const hash = hashes
    .reduce(
      (resultHash, {hash}) => resultHash.update(hash),
      crypto.createHash('md5')
    )
    .digest('hex');

  return `${hash}${options.debug ? '-debug' : ''}`;
}

function build(options) {
  if (options.template) {
    if (options.usedConfig) {
      throw new errorMessage.CustomError(
        /* eslint-disable prettier/prettier */
      'INCOMPATIBLE FLAGS',
      `You used both ${chalk.cyan('--config')} and ${chalk.cyan('--template')}, but these flags can't be used together.

Please remove one of them and try re-running.`,
        /* eslint-enable prettier/prettier */
      );
    }

    return buildFromGitHubTemplate(options);
  }

  return buildLocalProject(options);
}

async function buildLocalProject(options) {
  const userSrc = options.userSrc();
  const reviewElmJsonPath = path.join(userSrc, 'elm.json');

  const reviewElmJson = await fsReadJson(reviewElmJsonPath).catch((error) => {
    if (error.code === 'ENOENT') {
      return Promise.reject(
        new errorMessage.CustomError(
          /* eslint-disable prettier/prettier */
'INCORRECT CONFIGURATION',
`I could not find a review configuration. I was expecting to find an ${chalk.yellowBright('elm.json')} file and a ${chalk.cyan('ReviewConfig.elm')} file in ${chalk.cyan(path.dirname(reviewElmJsonPath))}${chalk.cyan('/')}.

I can help set you up with an initial configuration if you run ${chalk.cyanBright('elm-review init')}.`,
options.elmJsonPath
          /* eslint-enable prettier/prettier */
        )
      );
    }

    return Promise.reject(error);
  });

  validateElmReviewVersion(options, reviewElmJsonPath, reviewElmJson);

  const appHash = await cachedBuild(
    options,
    userSrc,
    reviewElmJsonPath,
    reviewElmJson
  );

  let elmModulePath = options.elmModulePath(appHash);
  if (fs.existsSync(elmModulePath)) {
    Debug.log(
      `Review application is already built. Using ${Anonymize.path(
        options,
        elmModulePath
      )}`
    );
  } else {
    const buildFolder = temp.mkdirSync('elm-review-app');
    Debug.log('Starting review application build');

    const buildResult = await Promise.all([
      getElmBinary(options),
      createTemplateProject(
        options,
        reviewElmJsonPath,
        userSrc,
        buildFolder,
        reviewElmJson
      )
    ]).then(([elmBinary]) => {
      Debug.log('Compiling review application');
      return compileElmProject(options, buildFolder, elmModulePath, elmBinary);
    });

    if (buildResult) {
      Debug.log('Finished review application build');
    } else {
      elmModulePath = null;
    }
  }

  return {
    elmModulePath,
    reviewElmJsonPath,
    reviewElmJson
  };
}

async function buildFromGitHubTemplate(options) {
  const commit = await getRelevantCommit(options);
  const reviewElmJson = await getRemoteElmJson(options, commit);
  Debug.log(`Commit is: ${commit}`);

  // TODO Fail if elmJson contains paths to '../xyz', that will make things easier
  let elmModulePath = options.templateElmModulePath(commit);
  if (fs.existsSync(elmModulePath)) {
    Debug.log(
      `Review application is already built. Using ${Anonymize.path(
        options,
        elmModulePath
      )}`
    );
  } else {
    const reviewElmJsonPath = options.pathToTemplateElmJson(commit);

    validateElmReviewVersion(options, reviewElmJsonPath, reviewElmJson);

    const buildFolder = temp.mkdirSync('elm-review-app');

    // Download all files from the template
    await Promise.all(
      reviewElmJson['source-directories'].map((sourceDirectory) =>
        downloadDirectory(options, commit, buildFolder, sourceDirectory)
      )
    );

    Debug.log('Starting template review application build');

    const buildResult = await Promise.all([
      getElmBinary(options),
      createTemplateProject(
        options,
        reviewElmJsonPath,
        buildFolder,
        buildFolder,
        reviewElmJson
      )
    ]).then(([elmBinary]) => {
      Debug.log('Compiling template review application');
      return compileElmProject(options, buildFolder, elmModulePath, elmBinary);
    });

    if (buildResult) {
      Debug.log('Finished template review application build');
    } else {
      elmModulePath = null;
    }
  }

  return {
    elmModulePath,
    reviewElmJsonPath: null,
    reviewElmJson
  };
}

function getRelevantCommit(options) {
  return options.template.reference
    ? getLatestCommitForReference(options, options.template.reference)
    : findDefaultBranch(options).then((defaultBranch) => {
        Debug.log(`Default branch is: ${defaultBranch}`);
        return getLatestCommitForReference(options, defaultBranch);
      });
}

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
many times`
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

        return download(
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

function download(url, dest) {
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

async function createTemplateProject(
  options,
  reviewElmJsonPath,
  userSrc,
  dest,
  reviewElmJson
) {
  // Destination directories
  const projectFolder = path.join(dest, 'project');
  const elmJsonPath = path.join(projectFolder, 'elm.json');

  // Load review project's elm.json file contents
  const dependencies = await templateDependencies.get(
    options,
    reviewElmJson.dependencies,
    reviewElmJsonPath
  );
  await fsEnsureDir(path.dirname(elmJsonPath));
  return writeElmJsonFile(options, userSrc, elmJsonPath, {
    ...reviewElmJson,
    dependencies
  });
}

function writeElmJsonFile(options, userSrc, elmJsonPath, elmJson) {
  const elmJsonWithSourceDirectories = updateSourceDirectories(
    options,
    userSrc,
    elmJson
  );

  return fsWriteFile(
    elmJsonPath,
    JSON.stringify(elmJsonWithSourceDirectories, null, 4)
  );
}

function updateSourceDirectories(options, userSrc, elmJson) {
  const sourceDirectories = elmJson['source-directories']
    .map((directory) => path.resolve(userSrc, directory))
    .concat([path.resolve(templateSrc)])
    .concat(
      options.localElmReviewSrc
        ? [path.resolve(userSrc, options.localElmReviewSrc)]
        : []
    );

  return {
    ...elmJson,
    'source-directories': sourceDirectories
  };
}

function compileElmProject(options, dest, elmModulePath, elmBinary) {
  const compileOptions = {
    cwd: path.join(dest, 'project'),
    output: elmModulePath,
    debug: Boolean(options.debug),
    optimize: !options.debug,
    verbose: false,
    warn: false,
    report: 'json',
    pathToElm: elmBinary,
    processOpts: {
      env: process.env,
      stdio: ['ignore', 'ignore', 'pipe']
    }
  };

  const compileTarget = [`${templateSrc}/Elm/Review/Main.elm`];

  return new Promise((resolve) => {
    const compileProcess = elmCompiler.compile(compileTarget, compileOptions);

    let stderr = '';
    if (compileProcess.stderr) {
      compileProcess.stderr.on('data', (data) => {
        stderr += data;
      });
    }

    compileProcess.on('close', (exitCode) => {
      if (exitCode === 0) {
        resolve(elmModulePath);
      } else {
        const {title, message} = compilationError(options, stderr);
        if (options.report === 'json') {
          console.log(
            errorMessage.report(
              options,
              new errorMessage.CustomError(title, `${message}\n\n${stderr}`)
            )
          );
          return resolve(null);
        }

        // Re-running the compiler to print its errors in color.
        // We do this because piping stderr loses the color, which we use to
        // give different error messages based
        console.log(
          errorMessage.report(
            options,
            new errorMessage.CustomError(title, wrap(message, 80) + '\n\n')
          )
        );
        compileOptions.processOpts.stdio = ['ignore', 'ignore', 'inherit'];
        compileOptions.report = undefined;
        const compileProcessToGetColoredErrors = elmCompiler.compile(
          compileTarget,
          compileOptions
        );

        compileProcessToGetColoredErrors.on('close', () => {
          if (options.watch) {
            return resolve(null);
          }

          // eslint-disable-next-line unicorn/no-process-exit
          process.exit(1);
        });
      }
    });
  });
}

function compilationError(options, stderr) {
  if (stderr.includes('DEBUG REMNANTS')) {
    return {
      title: 'DEBUG IN CONFIGURATION',
      /* eslint-disable prettier/prettier */
      message: `You are using the ${chalk.yellow('Debug')} module in your configuration or rules, but I am compiling in optimized mode. Either remove those uses or run elm-review with ${chalk.yellow('--debug')}.`
      /* eslint-enable prettier/prettier */
    };
  }

  if (stderr.includes('MODULE NOT FOUND')) {
    return {
      title: 'MODULE NOT FOUND',
      /* eslint-disable prettier/prettier */
      message: `A module is missing in your configuration. Maybe you forgot to add some dependencies that contain the rules you wished to enable? If so, run ${chalk.cyanBright('elm install')} with the package name from inside ${chalk.yellowBright(options.userSrc(null))}.`
      /* eslint-enable prettier/prettier */
    };
  }

  return {
    title: 'CONFIGURATION COMPILATION ERROR',
    /* eslint-disable prettier/prettier */
    message: `An error occurred while compiling your configuration for ${chalk.greenBright('elm-review')}. I need your configuration to compile in order to know how to analyze your files. Hopefully the compiler error below will help you figure out how to fix it.`
    /* eslint-enable prettier/prettier */
  };
}

function validateElmReviewVersion(options, reviewElmJsonPath, reviewElmJson) {
  if (options.localElmReviewSrc) {
    return;
  }

  if (reviewElmJson.type !== 'application') {
    let pathToElmJson = reviewElmJsonPath;
    if (options.template) {
      const {repoName, pathToFolder = ''} = options.template;
      const pathToElmJsonInRepo = `${pathToFolder}/elm.json`
        .split('//')
        .join('/');
      pathToElmJson = `${repoName}'s ${pathToElmJsonInRepo}`;
    }

    throw new errorMessage.CustomError(
      /* eslint-disable prettier/prettier */
      'REVIEW CONFIG IS NOT AN APPLICATION',
      `I wanted to use ${chalk.yellow(pathToElmJson)} as the basis for the configuration, and I expected it to be an "application", but it wasn't.

I think it likely that you are pointing to an incorrect configuration file. Please check the path to your configuration again.`
      /* eslint-enable prettier/prettier */
    );
  }

  const elmReviewVersion =
    reviewElmJson.dependencies.direct['jfmengels/elm-review'];

  if (!elmReviewVersion) {
    if (options.template) {
      throw new errorMessage.CustomError(
        /* eslint-disable prettier/prettier */
'MISSING ELM-REVIEW DEPENDENCY',
`The template's configuration does not include ${chalk.greenBright('jfmengels/elm-review')} in its direct dependencies.

Maybe you chose the wrong template, or the template is malformed. If the latter is the case, please inform the template author.`
        /* eslint-enable prettier/prettier */
      );
    }

    throw new errorMessage.CustomError(
      /* eslint-disable prettier/prettier */
'MISSING ELM-REVIEW DEPENDENCY',
`${chalk.yellow(reviewElmJsonPath)} does not include ${chalk.greenBright('jfmengels/elm-review')} in its direct dependencies.

Please add it by running ${chalk.cyanBright('elm install jfmengels/elm-review')} inside
of ${chalk.yellow(path.dirname(reviewElmJsonPath))}.`
      /* eslint-enable prettier/prettier */
    );
  }

  const [major, minor] = elmReviewVersion.split('.');
  if (major === '2' && minor < Number.parseInt('1', 10)) {
    if (options.template) {
      throw new errorMessage.CustomError(
        /* eslint-disable prettier/prettier */
        'UNSUPPORTED ELM-REVIEW VERSION',
`The template uses an unsupported version of ${chalk.greenBright('jfmengels/elm-review')}. It is using v${elmReviewVersion}, but I need it to be 2.1.0 <= v < 3.0.0.

Please inform the template author and kindly ask him to update his configuration, or make a pull request to help them out.`
        /* eslint-enable prettier/prettier */
      );
    }

    throw new errorMessage.CustomError(
      /* eslint-disable prettier/prettier */
'UNSUPPORTED ELM-REVIEW VERSION',
`You are using ${chalk.greenBright('jfmengels/elm-review')} v${elmReviewVersion}, but I need it to be
2.1.0 <= v < 3.0.0.

Please upgrade your version by running
${chalk.cyanBright('npx elm-json install jfmengels/elm-review@2')} inside
of ${chalk.yellow(path.dirname(reviewElmJsonPath))}.`
      /* eslint-enable prettier/prettier */
    );
  }
}

module.exports = {build};

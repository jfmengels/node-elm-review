// Pretty much copy-pasted the script from rtfeldman/node-test-runner
// https://raw.githubusercontent.com/rtfeldman/node-test-runner/master/lib/install.js

/* eslint-disable no-prototype-builtins, unicorn/no-process-exit */

const path = require('path');
const childProcess = require('child_process');
const temp = require('temp');
const fs = require('fs-extra');

const description = `install USER/PACKAGE # Install a package which contains rules and add it to your "test-dependencies"`;

function installDependency(
  pathToElmBinary /* : string */,
  packageName /* : string */
) {
  let dirPath;

  // Automatically track and cleanup files at exit
  temp.track();

  try {
    dirPath = temp.mkdirSync('elm-lint-install-');
  } catch (error) {
    console.error(
      'Unable to create temporary directory for elm-lint install.',
      error
    );
    process.exit(1);
  }

  const elmJson = JSON.parse(fs.readFileSync('elm.json'));
  const tmpElmJsonPath = path.join(dirPath, 'elm.json');
  let isPackage;

  switch (elmJson.type) {
    case 'package':
      isPackage = true;
      break;

    case 'application':
      isPackage = false;
      break;

    default:
      console.error('Unrecognized elm.json type:', elmJson.type);
      process.exit(1);
  }

  // This mirrors the behavior of `elm install` passing a package that is
  // already installed. Say it is already installed, then exit 0.
  if (
    (isPackage && elmJson['test-dependencies'].hasOwnProperty(packageName)) ||
    (!isPackage &&
      elmJson['test-dependencies'].direct.hasOwnProperty(packageName))
  ) {
    console.log('It is already installed!');
    return;
  }

  const oldSourceDirectories = elmJson['source-directories'];

  // Without this, `elm install` will complain about missing source dirs
  // in the temp dir. This way we don't have to create them!
  elmJson['source-directories'] = ['.'];

  fs.writeFileSync(tmpElmJsonPath, JSON.stringify(elmJson), 'utf8');
  console.log(1);

  childProcess.execFileSync(pathToElmBinary, ['install', packageName], {
    stdio: 'inherit',
    cwd: dirPath
  });

  const newElmJson = JSON.parse(fs.readFileSync(tmpElmJsonPath, 'utf8'));

  if (isPackage) {
    Object.keys(newElmJson.dependencies).forEach(key => {
      if (!elmJson.dependencies.hasOwnProperty(key)) {
        // If we didn't have this dep before, move it to test-dependencies.
        newElmJson['test-dependencies'][key] = newElmJson.dependencies[key];

        delete newElmJson.dependencies[key];
      }
    });
  } else {
    moveToTestDeps(elmJson, newElmJson, 'direct');
    moveToTestDeps(elmJson, newElmJson, 'indirect');
  }

  // Restore the old source-directories value.
  newElmJson['source-directories'] = oldSourceDirectories;

  fs.writeFileSync(
    'elm.json',
    JSON.stringify(newElmJson, null, 4) + '\n',
    'utf8'
  );
}

function moveToTestDeps(elmJson, newElmJson, directness) {
  Object.keys(newElmJson.dependencies[directness]).forEach(key => {
    // If we didn't have this dep before, move it to test-dependencies.
    if (!elmJson.dependencies[directness].hasOwnProperty(key)) {
      // Don't put things in indirect test-dependencies if they
      // are already present in direct test-dependencies! See this issue:
      // https://github.com/rtfeldman/node-test-runner/issues/282
      if (
        directness === 'direct' ||
        !newElmJson['test-dependencies'].direct.hasOwnProperty(key)
      ) {
        newElmJson['test-dependencies'][directness][key] =
          newElmJson.dependencies[directness][key];
      }

      delete newElmJson.dependencies[directness][key];
    }
  });
}

module.exports = {
  installDependency,
  description
};

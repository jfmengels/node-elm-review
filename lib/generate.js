// @flow

const path = require('path');

function generatePackageJson() {
  const elmPackage = {};
  const elmRootDir = path.resolve(Runner.findNearestElmPackageDir(testFilePaths));
  const originalDir = path.resolve(Runner.findNearestElmPackageDir([path.resolve(elmRootDir, "..")]));
  const elmPackagePath = path.resolve(path.join(elmRootDir, "elm-package.json"));

  const newElmPackageDir = path.resolve(elmRootDir, generatedCodeDir);
  const generatedSrc = path.join(newElmPackageDir, "src");

  const elmPackageContents = {};

  try {
    elmPackageContents = fs.readJsonSync(elmPackagePath);
  } catch (err) {
    console.error("Error reading elm-package.json: " + err);
    process.exit(1);
  }

  // Enable Native modules in the new elm-package.json, so we can import
  // the function that translates runtime exceptions into test failures.
  elmPackageContents["native-modules"] = true;

  // TODO remove these next two conditionals once random-pcg has become core's new Random!
  if (!elmPackageContents.dependencies) {
    elmPackageContents.dependencies = [];
  }


  // $FlowFixMe
  if (!elmPackageContents.dependencies["mgold/elm-random-pcg"]) {
    // Test.Runner.Node.App needs this to create a Seed from the current timestamp
    // $FlowFixMe
    elmPackageContents.dependencies["mgold/elm-random-pcg"] = "4.0.2 <= v < 6.0.0";
  }

  // Make all the source-directories absolute, and introduce a new one.
  const sourceDirs = (elmPackageContents["source-directories"] || []).map(function(src) {
    return path.resolve(src)
  });

  elmPackageContents["source-directories"] = [
    // Include elm-stuff/generated-sources - since we'll be generating sources in there.
    generatedSrc,

    // Include node-test-runner's src directory, to allow access to the Runner code.
    path.resolve(path.join(__dirname, "..", "src"))
  ].concat(sourceDirs)

  fs.mkdirpSync(newElmPackageDir);

  // Generate the new elm-package.json
  fs.writeFileSync(
    path.join(newElmPackageDir, "elm-package.json"),
    JSON.stringify(elmPackageContents, null, 4)
  );

  // Copy all the native-src files over. These need to be "localized" - that is,
  // in js they cannot define things using rtfeldman$node_test_runner - but rather
  // must use the appropriate package name from the elm-package.json we're copying.
  Runner.copyNativeSrcFiles(
    Runner.repositoryToNativePackageName(elmPackageContents.repository),
    path.join(__dirname, "..", "native-src"),
    generatedSrc
  );

  return [newElmPackageDir, generatedSrc, sourceDirs];
}


module.exports = {
  package: generatePackageJson
};

const got = require('got');

function collect(elmJson) {
  return Promise.all(
    Object.entries(elmJson.dependencies).map(
      async ([packageName, constraint]) => {
        const version = constraint.split(' ')[0];
        const response = await got(
          `https://package.elm-lang.org/packages/${packageName}/${version}/docs.json`
        );
        return {
          packageName,
          version,
          docsJson: response.body
        };
      }
    )
  );
}

module.exports = {
  collect
};

function makePathOsAgnostic(path_) {
  return path_.replace(/.:/, '').replace(/\\/g, '/');
}

module.exports = {
  makePathOsAgnostic
};

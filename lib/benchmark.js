module.exports = {
  start,
  end
};

function start(options, name) {
  if (options.showBenchmark) {
    console.time(name);
  }
}

function end(options, name) {
  if (options.showBenchmark) {
    console.timeEnd(name);
  }
}

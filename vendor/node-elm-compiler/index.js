'use strict';

var spawn = require("cross-spawn");
var elmBinaryName = "elm";
var fs = require("fs");
var path = require("path");
var temp = require("temp").track();

var defaultOptions = {
  spawn: spawn,
  cwd: undefined,
  pathToElm: undefined,
  help: undefined,
  output: undefined,
  report: undefined,
  debug: undefined,
  verbose: false,
  processOpts: undefined,
  docs: undefined,
  optimize: undefined,
};

var supportedOptions = Object.keys(defaultOptions);

function prepareSources(sources) {
  if (!(sources instanceof Array || typeof sources === "string")) {
    throw "compile() received neither an Array nor a String for its sources argument.";
  }

  return typeof sources === "string" ? [sources] : sources;
}

function prepareOptions(options, spawnFn) {
  return Object.assign({}, defaultOptions, options, { spawn: spawnFn });
}

function prepareProcessArgs(sources, options) {
  var preparedSources = prepareSources(sources);
  var compilerArgs = compilerArgsFromOptions(options);

  return ["make"].concat(preparedSources ? preparedSources.concat(compilerArgs) : compilerArgs);
}

function prepareProcessOpts(options) {
  var env = Object.assign({ LANG: 'en_US.UTF-8' }, process.env);
  return Object.assign({ env: env, stdio: "inherit", cwd: options.cwd }, options.processOpts);

}

function runCompiler(sources, options, pathToElm) {
  if (typeof options.spawn !== "function") {
    throw "options.spawn was a(n) " + (typeof options.spawn) + " instead of a function.";
  }

  var processArgs = prepareProcessArgs(sources, options);
  var processOpts = prepareProcessOpts(options);

  if (options.verbose) {
    console.log(["Running", pathToElm].concat(processArgs).join(" "));
  }

  return options.spawn(pathToElm, processArgs, processOpts);
}

function compilerErrorToString(err, pathToElm) {
  if ((typeof err === "object") && (typeof err.code === "string")) {
    switch (err.code) {
      case "ENOENT":
        return "Could not find Elm compiler \"" + pathToElm + "\". Is it installed?";

      case "EACCES":
        return "Elm compiler \"" + pathToElm + "\" did not have permission to run. Do you need to give it executable permissions?";

      default:
        return "Error attempting to run Elm compiler \"" + pathToElm + "\":\n" + err;
    }
  } else if ((typeof err === "object") && (typeof err.message === "string")) {
    return JSON.stringify(err.message);
  } else {
    return "Exception thrown when attempting to run Elm compiler " + JSON.stringify(pathToElm);
  }
}

function compile(sources, options) {
  var optionsWithDefaults = prepareOptions(options, options.spawn || spawn);
  var pathToElm = options.pathToElm || elmBinaryName;


  try {
    return runCompiler(sources, optionsWithDefaults, pathToElm)
      .on('error', function (err) { throw (err); });
  } catch (err) {
    throw compilerErrorToString(err, pathToElm);
  }
}

function getSuffix(outputPath, defaultSuffix) {
  if (outputPath) {
    return path.extname(outputPath) || defaultSuffix;
  } else {
    return defaultSuffix;
  }
}

// write compiled Elm to a string output
// returns a Promise which will contain a Buffer of the text
// If you want html instead of js, use options object to set
// output to a html file instead
// creates a temp file and deletes it after reading
function compileToString(sources, options) {
  var suffix = getSuffix(options.output, '.js');
  return new Promise(function (resolve, reject) {
      temp.open({ suffix: suffix }, function (err, info) {
          if (err) {
              return reject(err);
          }
          options.output = info.path;
          options.processOpts = { stdio: 'inherit' };
          var compiler;
          try {
              compiler = compile(sources, options);
          }
          catch (compileError) {
              return reject(compileError);
          }
          compiler.on("close", function (exitCode) {
              if (exitCode !== 0) {
                  return reject('Compilation failed');
              }
              else if (options.verbose) {
                  console.log(output);
              }
              fs.readFile(info.path, { encoding: "utf8" }, function (err, data) {
                  return err ? reject(err) : resolve(data);
              });
          });
      });
  });
}


function compileToStringSync(sources, options) {
  const suffix = getSuffix(options.output, '.js');

  const file = temp.openSync({ suffix });
  options.output = file.path;
  compileSync(sources, options);

  return fs.readFileSync(file.path, { encoding: "utf8" });
}

function flatten(array) {
  return array.reduce((res, element) => res.concat(element), [])
}

// Converts an object of key/value pairs to an array of arguments suitable
// to be passed to child_process.spawn for elm-make.
function compilerArgsFromOptions(options) {
  return flatten(Object.entries(options).map(function ([opt, value]) {
    if (value) {
      switch (opt) {
        case "spawn": return [];
        case "cwd": return [];
        case "pathToElm": return [];
        case "help": return ["--help"];
        case "output": return ["--output", value];
        case "report": return ["--report", value];
        case "debug": return ["--debug"];
        case "verbose": return [];
        case "processOpts": return [];
        case "docs": return ["--docs", value];
        case "optimize": return ["--optimize"];
        case "runtimeOptions": return ["+RTS", ...value, "-RTS"];
        default:
          throw new Error('node-elm-compiler was given an unrecognized Elm compiler option: ' + opt);
      }
    } else {
      return [];
    }
  }));
}

module.exports = {
  compile,
  compileToString: compileToString,
  compileToStringSync: compileToStringSync,
};

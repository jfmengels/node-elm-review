# elm-lint CLI

![](https://travis-ci.com/jfmengels/node-elm-lint.svg?branch=master)

Run [`elm-lint`] from Node.js.

**WARNING: This project is still under construction. The CLI for the latest version of elm-lint has not been released yet, and will not work.**

![elm-lint reporter output](https://github.com/jfmengels/node-elm-lint/blob/master/documentation/images/elm-lint-report.png?raw=true)

## Installation

```bash
# Save it to your package.json, if you use npm in your project.
# This is the recommended way.
npm install @jfmengels/elm-lint --save-dev

# Install globally. This is not recommended.
npm install -g @jfmengels/elm-lint
```

**Note**: Not to be confused with the `elm-lint` package, which has no relationship to this project.

## Usage

```bash
elm-lint --help  # Print the help
elm-lint init    # Creates an empty lint configuration
elm-lint         # Lint your project
```

## Configuration

To run `elm-lint` for the first time, you need to run

```bash
elm-lint init
elm-lint init --help # for more information and the available flags
```

This will create a `lint/` directory containing an `elm.json` and a `LintConfig.elm` file, which you should commit into your project. Here is what it may look like:

```elm
module LintConfig exposing (config)

import Lint.Rule exposing Rule
import NoDebug
import NoUnused.Variables


config : List Rule
config =
    [ NoDebug.rule
    , NoUnused.Variables.rule
    ]
```

The configuration consists of a list of linting rules. Import the rules you wish to use and add them to `config`.
Do note that some rules will need additional configuration, but don't worry, if you misconfigure `elm-lint`, the Elm compiler will tell you.

If you need to install packages to get third-party rules from the Elm packages, go inside the directory then run

```bash
cd lint/ # Go inside your lint configuration directory
elm install authorName/packageName
```

## Run linting

Once you're done configuring, run `elm-lint` to analyze your project.

You can also run `elm-lint --fix`. The CLI will present you fixes for the errors that offer an automatic fix, which you can then accept or not. When there are no more fixable errors left, elm-lint will report the remaining errors as if it was called without `--fix`. Fixed errors will be reformatted using [`elm-format`].

Run `elm-lint --help` for more information on the available flags.

```bash
elm-lint # Analyze your project
elm-lint --fix # Analyze your project and potentially proposes automatic fixes
elm-lint --help # for more information and the available flags
```


## Which parts of the project will be analyzed?

`elm-lint` targets a project, and therefore requires an `elm.json`. It will lint all the files of the project
  - For packages: all the Elm files in `src/`
  - For applications: all the Elm files in the `elm.json`'s `source-directories`

If you wish to also lint your tests directory or the lint configuration itself, you can use the `--extra` flag.

```bash
elm-lint --extra tests/ --extra lint/
```


## Exit status

If any rule from your configuration reports a pattern in one of the analyzed files, the process will exit with status 1. Otherwise, it will exit with status 0.

If the process fails at some point, it will exit with status 1.


## Why is there a need for a lint directory?

When the CLI uses looks at your configuration, it is in practice compiling an application using the configuration in your project, then running that application to analyze your project.

The CLI need at least two pieces of information from your configuration:
  - An `elm.json` file to know the external packages your configuration depends upon
  - A `LintConfig.elm` file that determines your configuration.

Your custom rules, unless you want to share them in the Elm package registry, should be in the `lint/` directory too, so as not to pollute your main project's dependencies. If they are in here, we need to include these custom rules and their dependencies in the application files.


[`elm-lint`]: https://github.com/jfmengels/elm-lint
[`elm-format`]: https://github.com/avh4/elm-format

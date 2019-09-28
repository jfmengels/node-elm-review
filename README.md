# elm-review CLI

![](https://travis-ci.com/jfmengels/node-elm-review.svg?branch=master)

Run [`elm-review`] from Node.js.

![elm-review reporter output](https://github.com/jfmengels/node-elm-review/blob/master/documentation/images/elm-review-report.png?raw=true)

## Installation

```bash
# Save it to your package.json, if you use npm in your project.
# This is the recommended way.
npm install elm-review --save-dev

# Install globally. This is not recommended.
npm install -g elm-review
```

## Usage

```bash
elm-review --help  # Print the help
elm-review init    # Creates an empty review configuration
elm-review         # Review your project
```

## Configuration

To run `elm-review` for the first time, you need to run

```bash
elm-review init
elm-review init --help # for more information and the available flags
```

This will create a `review/` directory containing an `elm.json` and a `ReviewConfig.elm` file, which you should commit into your project. Here is what it may look like:

```elm
module ReviewConfig exposing (config)

import Lint.Rule exposing Rule
import NoDebug
import NoUnused.Variables


config : List Rule
config =
    [ NoDebug.rule
    , NoUnused.Variables.rule
    ]
```

`elm-review` does not come with any built-in rules. You can read why [here](https://github.com/jfmengels/elm-review/blob/master/documentation/design/no-built-in-rules.md). You can find rules in the Elm package registry by [using `elm-search` and searching for `Lint.Rule.Rule`](https://klaftertief.github.io/elm-search/?q=Lint.Rule.Rule), and use them by going to your `review/` directory and running `elm install` in your terminal.

```bash
cd review/ # Go inside your review configuration directory
elm install authorName/packageName
```

## Run a review

Once you're done configuring, run `elm-review` to analyze your project.

You can also run `elm-review --fix`. The CLI will present you fixes for the errors that offer an automatic fix, which you can then accept or not. When there are no more fixable errors left, `elm-review` will report the remaining errors as if it was called without `--fix`. Fixed errors will be reformatted using [`elm-format`].

Run `elm-review --help` for more information on the available flags.

```bash
elm-review # Analyze your project
elm-review --fix # Analyze your project and potentially proposes automatic fixes
elm-review --help # for more information and the available flags
```


## Which parts of the project will be analyzed?

`elm-review` targets a project, and therefore requires an `elm.json`. It will review all the Elm files of the project
  - For packages: all the Elm files in `src/`
  - For applications: all the Elm files in the project's `elm.json`'s `source-directories`

If you wish to also review your tests directory or the review configuration itself,
then you should specify the directory of your project, or all the directories you want to be looked at.

```bash
# Review `src/` if project is a package, or the "source-directories" otherwise
elm-review
# Review all the Elm files in the current directory
elm-review .
# Review all the Elm files in the src/, tests/ and review/ directories
elm-review src/ tests/ review/
```


## Exit status

If any rule from your configuration reports an error in one of the analyzed files, the process will exit with status 1. Otherwise, it will exit with status 0.

If the process fails for any other reason (crash, misconfiguration, ...), it will exit with status 1.


## Why is there a need for a review/ directory?

When the CLI uses looks at your configuration, it is in practice compiling an application using the configuration in your project, then running that application to analyze your project.

The CLI need at least two pieces of information from your configuration:
  - An `elm.json` file to know the external packages your configuration depends upon, and the Elm version of your project
  - A `ReviewConfig.elm` file that determines your configuration

Your custom rules, unless you want to share them in the Elm package registry, should be in the `review/` directory too, so as not to pollute your main project's dependencies. If they are in here, we need to include these custom rules and their dependencies in the application files.


[`elm-review`]: https://github.com/jfmengels/elm-review
[`elm-format`]: https://github.com/avh4/elm-format

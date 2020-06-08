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
elm-review --help       # Print the help
elm-review              # Review your project
elm-review init         # Create an empty review configuration
elm-review new-package  # Create a new project containing elm-review rules
                        # aimed at being published on the Elm package registry
elm-review new-rule     # Create an empty new rule to get started.
                        # Very helpful for projects created with new-package
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

import Review.Rule exposing Rule
import NoDebug
import NoUnused.Variables


config : List Rule
config =
    [ NoDebug.rule
    , NoUnused.Variables.rule
    ]
```

`elm-review` does not come with any built-in rules. You can read why [here](https://github.com/jfmengels/elm-review/blob/master/documentation/design/no-built-in-rules.md). You can find rules in the Elm package registry by [using `elm-search` and searching for `Review.Rule.Rule`](https://klaftertief.github.io/elm-search/?q=Review.Rule.Rule), and use them by going to your `review/` directory and running `elm install` in your terminal.

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

`elm-review` targets a project, and therefore requires an `elm.json`. By default, it will review all the Elm files of the project and of the tests.
  - For packages: all the Elm files in `src/` and `tests/`
  - For applications: all the Elm files in `tests/` and in the project's `elm.json`'s `source-directories`

If you wish to, you can list the directories you wish to have reviewed, so as to review additional directories or to remove ignore some of directories, by adding them as arguments to the command line.

```bash
# Review `src/` if project is a package, or the "source-directories" otherwise, along with `tests/`
elm-review
# Review only the Elm files in the `src/Dashboard/`
elm-review src/Dashboard/
# Review all the Elm files in the src/, tests/ and review/ directories
elm-review src/ tests/ review/
# Review a specific file
elm-review src/Dashboard.elm
```

The recommended way to use `elm-review` is without arguments. It is best not to "remove" directories from the project, because some rules expect to have access to all the files in order to make the best analysis. If some data is missing, they may make incorrect reports. If you wish to ignore some files, it is best to handle that in the implementation and/or configuration of your rules.

If you add files that are not part of the project, you may run into different problems, such as conflicting module names (two `Main.elm` files), relying on different dependencies, etc. It is best to run `elm-review` once for each project, and depending on your needs, with different configurations (using the `--config` flag).


## Exit status

If any rule from your configuration reports an error in one of the analyzed files, the process will exit with status 1. Otherwise, it will exit with status 0.

If the process fails for any other reason (crash, misconfiguration, ...), it will exit with status 1.


## Why is there a need for a review/ directory?

When the CLI looks at your configuration, it is in practice compiling an application using the configuration in your project, then running that application to analyze your project.

The CLI need at least two pieces of information from your configuration:
  - An `elm.json` file to know the external packages your configuration depends upon (like the ones that contain the rules you enabled), and the Elm version of your project
  - A `ReviewConfig.elm` file that sets the rules to enforce for your project

Your custom rules, unless you want to share them in the Elm package registry, should be in the `review/` directory too, so as not to pollute your project's dependencies. If they are in here, we need to include these custom rules and their dependencies in the application files.


[`elm-review`]: https://github.com/jfmengels/elm-review
[`elm-format`]: https://github.com/avh4/elm-format


## Tooling integration

If you are interested in using `elm-review` inside a different environment than a terminal (like editors, CI, other Elm tools, ...), check out the documentation for [tooling integration](./documentation/tooling-integration.md).

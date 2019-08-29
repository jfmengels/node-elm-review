# elm-lint CLI

![](https://travis-ci.com/jfmengels/node-elm-lint.svg?branch=master)

Run [elm-lint] from Node.js.

**WARNING: This project is still under construction. The CLI for the latest version of elm-lint has not been released yet, and will not work.**

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
cd lint/ # Go inside your lint configuration folder
elm install authorName/packageName
```

Once you're done configuring, run `elm-lint` to analyze your project.

[elm-lint]: https://github.com/jfmengels/elm-lint

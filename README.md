# node-elm-lint

![](https://travis-ci.com/jfmengels/node-elm-lint.svg?branch=master)

Run [elm-lint] from Node.js.

## Installation

```bash
# Save it to your package.json, if you use npm in your project.
# This is the recommended way.
npm install node-elm-lint --save-dev

# Install globally. This is not recommended.
npm install -g node-elm-lint
```

## Usage

```bash
elm-lint --help  # Print the help
elm-lint init    # Creates a `LintConfig.elm` file in which you can declare how you want to configure elm-lint
elm-lint install # Install a package which contains rules and add it to your "test-dependencies"
elm-lint         # Lint your project
```

### Configuration

To run `elm-lint` for the first time, you need to run

```bash
elm-lint init
```

This will create a `LintConfig.elm` file at the root of your project, which you should commit into your project, which looks like the following:

```elm
module LintConfig exposing (config)

import Lint.Rule exposing Rule
import Lint.Rule.NoDebug
import Lint.Rule.NoUnusedVariables


config : List Rule
config =
    [ Lint.Rule.NoDebug.rule
    , Lint.Rule.NoUnusedVariables.rule
    ]
```

The configuration consists of a list of linting rules. Import the rules you wish to use and add them to `config`.
Do note that some rules will need additional configuration, but don't worry, if you misconfigure `elm-lint`, the Elm compiler will tell you.

If you need to install packages to get third-party rules, rather than use `elm install` which will add it to your `elm.json`'s `dependencies`, use `elm-lint install`, which will add them to your `elm.json`'s `test-dependencies`. Doing so will avoid polluting your dependencies, which you want to avoid especially if your project is a package.

```bash
# Good!
elm-lint install author/packagename
# Bad!
elm install author/packagename
```

Once you're done configuring, run `elm-lint` and you should be good to go.

[elm-lint]: https://github.com/jfmengels/elm-lint

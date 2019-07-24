# node-elm-lint

Run [elm-lint] from Node.js.

## Installation

```bash
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

import Lint.Types exposing (LintRule, Severity(..))
import Lint.Rules.NoDebug
import Lint.Rules.NoUnusedVariables


config : List ( Severity, LintRule )
config =
    [ ( Warning, Lint.Rules.NoDebug.rule )
    , ( Critical, Lint.Rules.NoUnusedVariables.rule )
    ]
```

The configuration consists of a list of linting rules. Rules are
Import the rules you wish to use and pair them with a severity level (`Critical` / `Warning`).
A reported `Critical` error will make `elm-lint` return a failure exit code, while a `Warning` error will not. You can see the full list of rules [here](https://github.com/jfmengels/elm-lint#rules).
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

# node-elm-lint

Run [elm-lint] from Node.js.

## Installation

```bash
npm install -g elm-lint
```

## Usage

```bash
elm-lint --help  # Print the help
elm-lint init    # Creates a `LintConfig.elm` file in which you can declare how you want to configure elm-lint
elm-lint         # Lint your project
```

### Configuration

To run `elm-lint` for the first time, you need to run

```bash
elm-lint init
```

This will create a `LintConfig.elm` file at the root of your project, which looks like the following:

```elm
module LintConfig exposing (config)

import Lint.Types exposing (LintRule, Severity(..))
import Lint.Rules.DefaultPatternPosition
import Lint.Rules.NoDebug
import Lint.Rules.NoUnusedVariables


config : List ( Severity, LintRule )
config =
    [ ( Critical, Lint.Rules.DefaultPatternPosition.rule { position = Lint.Rules.DefaultPatternPosition.Last } )
    , ( Warning, Lint.Rules.NoDebug.rule )
    , ( Critical, Lint.Rules.NoUnusedVariables.rule )
    ]
```

The configuration consists of a list of linting rules. Rules are
Import the rules you wish to use and pair them with a severity level (`Critical` / `Warning`).
A reported `Critical` error will make `elm-lint` return a failure exit code, while a `Warning` error will not. You can see the full list of rules [here](https://github.com/jfmengels/elm-lint#rules).
Do note that some rules will need additional configuration, but don't worry, if you misconfigure `elm-lint`, the Elm compiler will tell you.

Once you're done configuring, run `elm-lint` and you should be good to go.

### FAQ

- I get the error `(Critical) Parsing error: expected end of input` for some of my files, what is happening?

This means that your file could not be parsed.
You should try and copy-paste that file's source code into the [`elm-ast` online demo](http://bogdanp.github.io/elm-ast/example/) to see if you can reproduce the error. If you are able to, then try to make a minimal reproducible example and open an issue on [`elm-ast`](https://github.com/Bogdanp/elm-ast).

**In most cases**, this is due to comments made using `--` (e.g. `-- a comment`) that are not well handled by the parser. [elm-lint] tries to remove them before parsing, but does a bad job at it at the moment (help wanted).

- Thanks for pointing out the error, but I would like to know **where** in my code the error is.

At the moment, `elm-ast` is missing positional information on the generated AST, that `elm-lint` uses. You can follow [this issue](https://github.com/Bogdanp/elm-ast/issues/13) if you want to know more or to contribute.

- I have an idea for a rule, how can I get it integrated into elm-lint?

Please open an issue on [elm-lint] so we can talk about it. Try to make your proposal look like [this](https://github.com/eslint/eslint/blob/master/templates/rule-proposal.md).

[elm-lint] would like to be able to provide support for a plugin system so that you can work on it without my approval. Maybe that already works, but if it doesn't, please open an issue about that.

- The code looks bad and can be improved upon, also the documentation is lacking.

You're absolutely right. Please open an issue if you have suggestions or open a pull request!

[elm-lint]: https://github.com/jfmengels/elm-lint

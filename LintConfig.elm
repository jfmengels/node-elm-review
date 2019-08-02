module LintConfig exposing (config)

{-| Do not rename the module or the exposed function. `elm-lint` will look for
these.

To add packages that contain rules, run `elm-lint install author/packagename`
This will add the package to your `test-dependencies`, which will avoid
polluting your dependencies, which you want to avoid especially if your project
is a package.

-}

import Lint.Rule exposing (Rule)
import Lint.Rule.NoDebug
import Lint.Rule.NoExtraBooleanComparison
import Lint.Rule.NoImportingEverything
import Lint.Rule.NoUnusedTypeConstructors
import Lint.Rule.NoUnusedVariables


config : List Rule
config =
    [ Lint.Rule.NoDebug.rule
    , Lint.Rule.NoExtraBooleanComparison.rule
    , Lint.Rule.NoImportingEverything.rule { exceptions = [] }
    , Lint.Rule.NoUnusedVariables.rule
    , Lint.Rule.NoUnusedTypeConstructors.rule
    ]

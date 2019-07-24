module LintConfig exposing (config)

{-| Do not rename the module or the exposed function. `elm-lint` will look for
these.

To add packages that contain rules, run `elm-lint install author/packagename`
This will add the package to your `test-dependencies`, which will avoid
polluting your dependencies, which you want to avoid especially if your project
is a package.

-}

import Lint exposing (Severity(..))
import Lint.Rule exposing (Rule)
import Lint.Rule.NoDebug
import Lint.Rule.NoExtraBooleanComparison
import Lint.Rule.NoImportingEverything
import Lint.Rule.NoUnusedTypeConstructors
import Lint.Rule.NoUnusedVariables


config : List ( Severity, Rule )
config =
    [ ( Critical, Lint.Rule.NoDebug.rule )
    , ( Disabled, Lint.Rule.NoExtraBooleanComparison.rule )
    , ( Disabled, Lint.Rule.NoImportingEverything.rule { exceptions = [] } )
    , ( Critical, Lint.Rule.NoUnusedVariables.rule )
    , ( Critical, Lint.Rule.NoUnusedTypeConstructors.rule )
    ]

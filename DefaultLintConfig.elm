module LintConfig exposing (config)

-- Do not rename the module or the exposed function.
-- `elm-lint` will look for these.

import Lint exposing (Severity(..))
import Lint.Rule exposing (Rule)
import Lint.Rule.DefaultPatternPosition as DefaultPatternPosition
import Lint.Rule.NoDebug
import Lint.Rule.NoExtraBooleanComparison
import Lint.Rule.NoImportingEverything
import Lint.Rule.NoUnusedTypeConstructors
import Lint.Rule.NoUnusedVariables


config : List ( Severity, Rule )
config =
    [ ( Disabled, DefaultPatternPosition.rule DefaultPatternPosition.ShouldBeLast )
    , ( Critical, Lint.Rule.NoDebug.rule )
    , ( Disabled, Lint.Rule.NoExtraBooleanComparison.rule )
    , ( Disabled, Lint.Rule.NoImportingEverything.rule { exceptions = [] } )
    , ( Critical, Lint.Rule.NoUnusedVariables.rule )
    , ( Critical, Lint.Rule.NoUnusedTypeConstructors.rule )
    ]

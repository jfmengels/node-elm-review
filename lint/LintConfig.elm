module LintConfig exposing (config)

{-| Do not rename the LintConfig module or the config function, because
`elm-lint` will look for these.

To add packages that contain rules, add them to this lint project using

    `elm install author/packagename`

-}

import Lint.Rule exposing (Rule)
import NoUnused.TypeConstructors
import NoUnused.Variables


config : List Rule
config =
    [ NoUnused.Variables.rule
    , NoUnused.TypeConstructors.rule
    ]

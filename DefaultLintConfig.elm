module LintConfig exposing (config)

{-| Do not rename the LintConfig module or the config function, because
`elm-lint` will look for these.

To add packages that contain rules, add them to this lint project using

    `elm install author/packagename`

when inside the directory containing this file.

-}

import Lint.Rule exposing (Rule)


config : List Rule
config =
    []

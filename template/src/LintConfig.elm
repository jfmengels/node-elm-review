module LintConfig exposing (config)

{-| Do not rename the module or the exposed function. `elm-lint` will look for
these.

To add packages that contain rules, in your terminal, go to this lint directory,
then run `elm install author/packagename`.

-}

import Lint.Rule exposing (Rule)


config : List Rule
config =
    []

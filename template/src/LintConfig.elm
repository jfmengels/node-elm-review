module LintConfig exposing (config)

{-| Do not rename the module or the exposed function. `elm-lint` will look for
these.

To add packages that contain rules, run `elm-lint install author/packagename`
This will add the package to your `test-dependencies`, which will avoid
polluting your dependencies, which you want to avoid especially if your project
is a package.

-}

import Lint.Rule exposing (Rule)


config : List Rule
config =
    []

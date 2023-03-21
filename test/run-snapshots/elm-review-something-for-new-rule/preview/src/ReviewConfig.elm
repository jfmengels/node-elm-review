module ReviewConfig exposing (config)

{-| Do not rename the ReviewConfig module or the config function, because
`elm-review` will look for these.

To add packages that contain rules, add them to this review project using

    `elm install author/packagename`

when inside the directory containing this file.

-}

import No.Doing.Foo
import Review.Rule exposing (Rule)
import SomeModuleRule
import SomeProjectRule


config : List Rule
config =
    [ No.Doing.Foo.rule
    , SomeProjectRule.rule
    , SomeModuleRule.rule
    ]

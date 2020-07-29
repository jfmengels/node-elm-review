module No.Doing.Foo exposing (rule)

{-|

@docs rule

-}

import Review.Rule as Rule exposing (Rule)


{-| Reports... REPLACEME

    config =
        [ No.Doing.Foo.rule
        ]


## Fail

    a =
        "REPLACEME example to replace"


## Success

    a =
        "REPLACEME example to replace"


## When (not) to enable this rule

This rule is useful when REPLACEME.
THis rule is not useful when REPLACEME.

-}
rule : Rule
rule =
    Rule.newModuleRuleSchema "No.Doing.Foo" ()
        -- Add your visitors
        |> Rule.fromModuleRuleSchema

module SomeRule exposing (rule)

{-|

@docs rule

-}

import Review.Rule as Rule exposing (Rule)


{-| Reports... REPLACEME

    config =
        [ SomeRule.rule
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
    Rule.newModuleRuleSchema "SomeRule" ()
        -- Add your visitors
        |> Rule.fromModuleRuleSchema

module Wrapper.Options.RuleType exposing
    ( RuleType(..)
    , fromString
    )


type RuleType
    = ModuleRule
    | ProjectRule


fromString : String -> Maybe RuleType
fromString type_ =
    if type_ == "module" then
        Just ModuleRule

    else if type_ == "project" then
        Just ProjectRule

    else
        Nothing

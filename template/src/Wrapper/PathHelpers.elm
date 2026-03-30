module Wrapper.PathHelpers exposing (format)

import Regex


{-| Format a path so that you can `cd` it.
-}
format : String -> String
format path =
    Regex.replace
        ("([^\\w%+,./:=@-])"
            |> Regex.fromString
            |> Maybe.withDefault Regex.never
        )
        (\{ match } -> "\\" ++ match)
        path

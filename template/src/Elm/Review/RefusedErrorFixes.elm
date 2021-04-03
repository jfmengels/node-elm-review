module Elm.Review.RefusedErrorFixes exposing (RefusedErrorFixes, empty, insert, member)

{-| Keeps track of error fixes that the user refused to apply.

@docs RefusedErrorFixes, empty, insert, member, memberForReporterError

-}

import Elm.Syntax.Range exposing (Range)
import Review.Rule as Rule exposing (ReviewError)
import Set exposing (Set)


{-| Contains the list of ignored error fixes.
-}
type RefusedErrorFixes
    = RefusedErrorFixes (Set String)


{-| Create an empty list of ignored error fixes.
-}
empty : RefusedErrorFixes
empty =
    RefusedErrorFixes Set.empty


{-| Insert an error in the list of refused error fixes.
-}
insert : ReviewError -> RefusedErrorFixes -> RefusedErrorFixes
insert error (RefusedErrorFixes refusedErrorFixes) =
    refusedErrorFixes
        |> Set.insert (errorKey error)
        |> RefusedErrorFixes


{-| Determine if the error has been refused.
-}
member : ReviewError -> RefusedErrorFixes -> Bool
member error (RefusedErrorFixes refusedErrorFixes) =
    Set.member (errorKey error) refusedErrorFixes


errorKey : ReviewError -> String
errorKey error =
    let
        range : Range
        range =
            Rule.errorRange error
    in
    String.join "###"
        [ Rule.errorRuleName error
        , Rule.errorMessage error
        , Rule.errorDetails error |> String.join "\n"
        , [ range.start.row
          , range.start.column
          , range.end.row
          , range.end.column
          ]
            |> List.map String.fromInt
            |> String.join "-"
        ]

module Elm.Review.RefusedErrorFixes exposing (RefusedErrorFixes, empty, insert, memberUsingRecord)

{-| Keeps track of error fixes that the user refused to apply.

@docs RefusedErrorFixes, empty, insert, memberUsingRecord

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
memberUsingRecord : { ruleName : String, filePath : String, message : String, details : List String, range : Range } -> RefusedErrorFixes -> Bool
memberUsingRecord error (RefusedErrorFixes refusedErrorFixes) =
    Set.member (errorKeyUsingRecord error) refusedErrorFixes


errorKey : ReviewError -> String
errorKey error =
    let
        range : Range
        range =
            Rule.errorRange error
    in
    String.join "###"
        [ Rule.errorRuleName error
        , Rule.errorFilePath error
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


errorKeyUsingRecord : { ruleName : String, filePath : String, message : String, details : List String, range : Range } -> String
errorKeyUsingRecord error =
    String.join "###"
        [ error.ruleName
        , error.filePath
        , error.message
        , error.details |> String.join "\n"
        , [ error.range.start.row
          , error.range.start.column
          , error.range.end.row
          , error.range.end.column
          ]
            |> List.map String.fromInt
            |> String.join "-"
        ]

module Elm.Lint.RefusedErrorFixes exposing
    ( RefusedErrorFixes, insert, member
    , empty
    )

{-| Keeps track of error fixes that the user refused to apply.

@docs RefusedErrorFixes, insert, member

-}

import Elm.Syntax.Range exposing (Range)
import Lint
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
insert : Lint.Error -> RefusedErrorFixes -> RefusedErrorFixes
insert error (RefusedErrorFixes refusedErrorFixes) =
    refusedErrorFixes
        |> Set.insert (errorKey error)
        |> RefusedErrorFixes


{-| Determine if the error has been refused.
-}
member : Lint.Error -> RefusedErrorFixes -> Bool
member error (RefusedErrorFixes refusedErrorFixes) =
    Set.member (errorKey error) refusedErrorFixes


errorKey : Lint.Error -> String
errorKey error =
    let
        range : Range
        range =
            Lint.errorRange error
    in
    String.join "###"
        [ Lint.errorRuleName error
        , Lint.errorModuleName error |> Maybe.withDefault "unknown module name"
        , Lint.errorMessage error
        , Lint.errorDetails error |> String.join "\n"
        , [ range.start.row
          , range.start.column
          , range.end.row
          , range.end.column
          ]
            |> List.map String.fromInt
            |> String.join "-"
        ]

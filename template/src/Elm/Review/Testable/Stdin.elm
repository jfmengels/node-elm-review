module Elm.Review.Testable.Stdin exposing
    ( readKey
    , readLine
    , toProblem
    )

{-|

@docs readKey
@docs readLine
@docs toProblem

-}

import Elm.Review.Testable.Internal as Internal
import Elm.Review.Testable.StdinData as StdinData exposing (Key, StdinError)
import ElmReview.Color exposing (Color(..))
import ElmReview.Problem as Problem exposing (Problem)


{-| Read a single keypress.
-}
readKey : Internal.TTask StdinError Key
readKey =
    Internal.ReadKey Internal.resultFromResult


{-| Read a single keypress.
-}
readLine : Internal.TTask StdinError String
readLine =
    Internal.ReadLine Internal.resultFromResult


toProblem : String -> StdinError -> Problem
toProblem stepDescription err =
    case err of
        StdinData.PermissionDenied ->
            Problem.unexpectedError stepDescription "PermissionDenied"

        StdinData.EndOfInput ->
            Problem.unexpectedError stepDescription "Reached end of input"

        StdinData.IoError message ->
            Problem.unexpectedError stepDescription message

        StdinData.NoStdin ->
            { title = "MISSING INPUT"
            , message = \c -> "I am missing information that I wanted to prompt for, but I can't access " ++ c Yellow "stdin" ++ " to do so."
            }
                |> Problem.from Problem.Unrecoverable

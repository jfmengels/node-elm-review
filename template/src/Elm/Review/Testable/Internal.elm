module Elm.Review.Testable.Internal exposing
    ( Cmd(..)
    , Task(..), TaskResult(..), resultFromResult
    )

{-|

@docs Cmd
@docs Task, TaskResult, resultFromResult

-}

import Elm.Review.Testable.Fs exposing (FsError, MatchKind)
import ElmReview.Path exposing (Path)


type Cmd msg
    = None
    | TaskCmd (Task msg msg)
    | Batch (List (Cmd msg))


type Task error value
    = ImmediateTask (TaskResult error value)
    | CreateDirectory Path (Result FsError () -> TaskResult error value)
    | WalkTree Path (Maybe String) MatchKind (Result FsError (List Path) -> TaskResult error value)


type TaskResult error value
    = Success value
    | Failure error
    | Continue (Task error value)


resultFromResult : Result error value -> TaskResult error value
resultFromResult result =
    case result of
        Ok value ->
            Success value

        Err error ->
            Failure error

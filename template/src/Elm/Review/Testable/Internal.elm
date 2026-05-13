module Elm.Review.Testable.Internal exposing
    ( Cmd(..)
    , Task(..), TaskResult(..), resultFromResult
    )

{-|

@docs Cmd
@docs Task, TaskResult, resultFromResult

-}

import Elm.Review.Testable.FsData exposing (FileStat, FsError, MatchKind)
import ElmReview.Path exposing (Path)


type Cmd msg
    = None
    | TaskCmd (Task msg msg)
    | Batch (List (Cmd msg))


type Task error value
    = ImmediateTask (TaskResult error value)
    | Stat Path (Result FsError FileStat -> TaskResult error value)
    | ReadTextFile Path (Result FsError String -> TaskResult error value)
    | WriteTextFile Path String (Result FsError () -> TaskResult error value)
    | DeleteFile Path (Result FsError () -> TaskResult error value)
    | CreateDirectory Path (Result FsError () -> TaskResult error value)
    | RemoveDirectory Path (Result FsError () -> TaskResult error value)
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

module Elm.Review.Testable.Internal exposing
    ( Cmd(..)
    , TTask(..), TaskResult(..), resultFromResult
    )

{-|

@docs Cmd
@docs TTask, TaskResult, resultFromResult

-}

import Elm.Review.Testable.FsData exposing (FileStat, FsError, MatchKind)
import Elm.Review.Testable.ProcessData exposing (Completed, ProcessError, ProcessId, SpawnError, SpawnOptions)
import Elm.Review.Testable.StdinData exposing (Key, StdinError)
import ElmReview.Path exposing (Path)


type Cmd msg
    = None
    | TaskCmd (TTask msg msg)
    | Batch (List (Cmd msg))


{-| "TTask" stands for "Testable Task".
-}
type TTask error value
    = ImmediateTask (TaskResult error value)
      -- File system
    | Stat Path (Result FsError FileStat -> TaskResult error value)
    | ReadTextFile Path (Result FsError String -> TaskResult error value)
    | WriteTextFile Path String (Result FsError () -> TaskResult error value)
    | DeleteFile Path (Result FsError () -> TaskResult error value)
    | CreateDirectory Path (Result FsError () -> TaskResult error value)
    | RemoveDirectory Path (Result FsError () -> TaskResult error value)
    | CopyDirectory { from : Path, to : Path } (Result SpawnError () -> TaskResult error value)
    | WalkTree Path (Maybe String) MatchKind (Result FsError (List Path) -> TaskResult error value)
      -- Stdin
    | ReadKey (Result StdinError Key -> TaskResult error value)
      -- Process
    | RunProcess String SpawnOptions (Result SpawnError Completed -> TaskResult error value)
    | SpawnProcess String SpawnOptions (Result SpawnError ProcessId -> TaskResult error value)


type TaskResult error value
    = Success value
    | Failure error
    | Continue (TTask error value)


resultFromResult : Result error value -> TaskResult error value
resultFromResult result =
    case result of
        Ok value ->
            Success value

        Err error ->
            Failure error

module Elm.Review.Testable.Process exposing (kill, run, spawn, wait)

import Elm.Review.Testable.Internal as Internal
import Elm.Review.Testable.ProcessData exposing (Completed, ProcessError, ProcessId, SpawnError, SpawnOptions)
import Elm.Review.Testable.StdinData exposing (Key, StdinError)


run : String -> SpawnOptions -> Internal.TTask SpawnError Completed
run command spawnOptions =
    Internal.RunProcess command spawnOptions Internal.resultFromResult


spawn : String -> SpawnOptions -> Internal.TTask ProcessError ProcessId
spawn command spawnOptions =
    Internal.SpawnProcess command spawnOptions Internal.resultFromResult


wait : ProcessId -> Internal.TTask ProcessError Completed
wait pid =
    Internal.WaitProcess pid Internal.resultFromResult


kill : ProcessId -> Int -> Internal.TTask ProcessError ()
kill pid signal =
    Internal.KillProcess pid signal Internal.resultFromResult

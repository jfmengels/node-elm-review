module Elm.Review.Testable.Process exposing (run)

import Elm.Review.Testable.Internal as Internal
import Elm.Review.Testable.ProcessData exposing (Completed, ProcessId, SpawnError, SpawnOptions)
import Elm.Review.Testable.StdinData exposing (Key, StdinError)


run : String -> SpawnOptions -> Internal.TTask SpawnError Completed
run command spawnOptions =
    Internal.RunProcess command spawnOptions Internal.resultFromResult


spawn : String -> SpawnOptions -> Internal.TTask SpawnError ProcessId
spawn command spawnOptions =
    Internal.SpawnProcess command spawnOptions Internal.resultFromResult

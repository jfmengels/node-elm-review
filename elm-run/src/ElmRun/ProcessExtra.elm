module ElmRun.ProcessExtra exposing
    ( errorToString, stdoutSpec
    , SpawnError(..), runButFailOnError
    )

{-|

@docs errorToString, stdoutSpec
@docs SpawnError, runButFailOnError

-}

import Os exposing (ProcessCapability)
import Os.Process as Process exposing (ProcessError)
import Task exposing (Task)


errorToString : ProcessError -> String
errorToString err =
    case err of
        Process.PermissionDenied ->
            "PermissionDenied"

        Process.CaptureLimitExceeded stream ->
            "CaptureLimitExceeded(" ++ stream ++ ")"

        Process.ProcessError message ->
            message


stdoutSpec : Bool -> Process.StdoutSpec
stdoutSpec debug =
    if debug then
        Process.InheritStdout

    else
        Process.NullStdout


type SpawnError
    = CommandNotFound
    | ProcessError ProcessError
    | CommandFailed Process.Completed


{-| Like `Os.Process.run`, but fails if the exit code is different from 0.
-}
runButFailOnError :
    ProcessCapability
    -> String
    -> Process.SpawnOptions
    -> Task SpawnError Process.Completed
runButFailOnError os command spawnOptions =
    Process.run os command spawnOptions
        |> Task.mapError ProcessError
        |> Task.andThen
            (\completed ->
                if completed.exitCode == 0 then
                    Task.succeed completed

                else if completed.exitCode == commandNotFound then
                    Task.fail CommandNotFound

                else
                    Task.fail (CommandFailed completed)
            )


{-| Error code when command was not found.
-}
commandNotFound : Int
commandNotFound =
    127

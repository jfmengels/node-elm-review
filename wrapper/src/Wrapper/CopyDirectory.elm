module Wrapper.CopyDirectory exposing (copyDirectory)

import Os exposing (ProcessCapability)
import Os.Process as Process exposing (ProcessError, defaultSpawnOptions)
import Task exposing (Task)
import Wrapper.Path exposing (Path)
import Wrapper.Problem as Problem exposing (Problem)


{-| Remove this when elm-run provides this functionality.
-}
copyDirectory : ProcessCapability -> { from : Path, to : Path } -> Task Problem ()
copyDirectory os { from, to } =
    Process.run os
        "cp"
        { defaultSpawnOptions
            | args = [ "-R", from, to ]
            , stdout = Process.NullStdout
            , stderr = Process.NullStderr
        }
        |> Task.map (\_ -> ())
        |> Task.mapError processingErrorToProblem


processingErrorToProblem : ProcessError -> Problem
processingErrorToProblem error =
    Problem.unexpectedError (processErrorToString error)


processErrorToString : ProcessError -> String
processErrorToString err =
    case err of
        Process.PermissionDenied ->
            "PermissionDenied"

        Process.CaptureLimitExceeded stream ->
            "CaptureLimitExceeded(" ++ stream ++ ")"

        Process.ProcessError message ->
            message

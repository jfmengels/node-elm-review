module ElmRun.OsExtra exposing (errorToString, which)

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


{-| Find the path to a command.
-}
which : ProcessCapability -> String -> Task ProcessError (Maybe String)
which os command =
    Process.run os
        "which"
        { cwd = Nothing
        , env = Nothing
        , args = [ command ]
        , stdin = Process.NullStdin
        , stdout = Process.CaptureStdout { maxBytes = 4096, onOverflow = Process.TruncateOutput }
        , stderr = Process.NullStderr
        }
        |> Task.map .stdout

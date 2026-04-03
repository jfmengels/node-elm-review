module ElmRun.OsExtra exposing (errorToString)

import Os.Process as Process exposing (ProcessError)


errorToString : ProcessError -> String
errorToString err =
    case err of
        Process.PermissionDenied ->
            "PermissionDenied"

        Process.CaptureLimitExceeded stream ->
            "CaptureLimitExceeded(" ++ stream ++ ")"

        Process.ProcessError message ->
            message

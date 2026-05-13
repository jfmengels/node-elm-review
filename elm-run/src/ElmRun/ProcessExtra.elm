module ElmRun.ProcessExtra exposing (errorToString, stdoutSpec)

{-|

@docs errorToString, stdoutSpec

-}

import Elm.Review.Testable.ProcessData as ProcessData exposing (ProcessError)


errorToString : ProcessError -> String
errorToString err =
    case err of
        ProcessData.PermissionDenied ->
            "PermissionDenied"

        ProcessData.CaptureLimitExceeded stream ->
            "CaptureLimitExceeded(" ++ stream ++ ")"

        ProcessData.ProcessError message ->
            message


stdoutSpec : Bool -> ProcessData.StdoutSpec
stdoutSpec debug =
    if debug then
        ProcessData.InheritStdout

    else
        ProcessData.NullStdout

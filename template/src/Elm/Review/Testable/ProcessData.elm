module Elm.Review.Testable.ProcessData exposing
    ( CaptureLimit
    , Completed
    , OverflowPolicy(..)
    , ProcessError(..)
    , ProcessId
    , SpawnError(..)
    , SpawnOptions
    , Spawned
    , StderrSpec(..)
    , StdinSpec(..)
    , StdoutSpec(..)
    , errorToString
    , stdoutSpec
    )


type SpawnError
    = CommandNotFound
    | ProcessRunError ProcessError
    | CommandFailed Completed


type ProcessError
    = PermissionDenied
    | CaptureLimitExceeded String
    | ProcessError String


type alias SpawnOptions =
    { args : List String
    , cwd : Maybe String
    , env : Maybe (List ( String, String ))
    , stdin : StdinSpec
    , stdout : StdoutSpec
    , stderr : StderrSpec
    }


type OverflowPolicy
    = FailProcess
    | TruncateOutput


type alias CaptureLimit =
    { maxBytes : Int
    , onOverflow : OverflowPolicy
    }


type StdinSpec
    = InheritStdin
    | NullStdin
    | TextStdin String
    | FileStdin String


type StdoutSpec
    = InheritStdout
    | NullStdout
    | CaptureStdout CaptureLimit


type StderrSpec
    = InheritStderr
    | NullStderr
    | CaptureStderr CaptureLimit
    | MergeWithStdout


type alias ProcessId =
    Int


type alias Spawned =
    { pid : ProcessId
    }


type alias Completed =
    { pid : ProcessId
    , exitCode : Int
    , signal : Maybe Int
    , stdout : Maybe String
    , stderr : Maybe String
    , stdoutTruncated : Bool
    , stderrTruncated : Bool
    }


errorToString : ProcessError -> String
errorToString err =
    case err of
        PermissionDenied ->
            "PermissionDenied"

        CaptureLimitExceeded stream ->
            "CaptureLimitExceeded(" ++ stream ++ ")"

        ProcessError message ->
            message


stdoutSpec : Bool -> StdoutSpec
stdoutSpec debug =
    if debug then
        InheritStdout

    else
        NullStdout

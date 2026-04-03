module ElmRun.FsExtra exposing (copyDirectory, errorToString)

import Fs exposing (FsError)
import Os exposing (ProcessCapability)
import Os.Process as Process exposing (ProcessError)
import Task exposing (Task)


errorToString : FsError -> String
errorToString fsError =
    case fsError of
        Fs.NotFound path ->
            "File not found: " ++ path

        Fs.PermissionDenied ->
            "Permission denied"

        Fs.IoError msg ->
            "Unknown error: " ++ msg


{-| Remove this when elm-run provides this functionality.

TODO Also remove the dependency to elm-run/os in Build.addReviewAppDependencies

-}
copyDirectory : ProcessCapability -> { from : String, to : String } -> Task ProcessError ()
copyDirectory os { from, to } =
    Process.run os
        "cp"
        { cwd = Nothing
        , env = Nothing
        , args = [ "-R", from, to ]
        , stdin = Process.NullStdin
        , stdout = Process.NullStdout
        , stderr = Process.NullStderr
        }
        |> Task.map (\_ -> ())

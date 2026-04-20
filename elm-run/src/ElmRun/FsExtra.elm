module ElmRun.FsExtra exposing
    ( errorToString
    , createFileAndItsDirectory
    , copyDirectory
    )

{-|

@docs errorToString
@docs createFileAndItsDirectory
@docs copyDirectory

-}

import ElmReview.Path as Path exposing (Path)
import Fs exposing (FileSystem, FsError)
import Os exposing (ProcessCapability)
import Os.Process as Process exposing (ProcessError)
import Task exposing (Task)


createFileAndItsDirectory : FileSystem -> Path -> String -> Task FsError ()
createFileAndItsDirectory fs path content =
    Fs.createDirectory fs (Path.dirname path)
        |> Task.andThen (\() -> Fs.writeTextFile fs path content)


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

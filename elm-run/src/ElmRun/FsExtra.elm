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

import Elm.Review.Testable.Fs as Fs
import Elm.Review.Testable.FsData as FsData exposing (FsError)
import Elm.Review.Testable.Process as Process
import Elm.Review.Testable.ProcessData as ProcessData exposing (SpawnError)
import Elm.Review.Testable.TTask as TTask exposing (TTask)
import ElmReview.Path as Path exposing (Path)


createFileAndItsDirectory : Path -> String -> TTask FsError ()
createFileAndItsDirectory path content =
    Fs.createDirectory (Path.dirname path)
        |> TTask.andThen (\() -> Fs.writeTextFile path content)


errorToString : FsError -> String
errorToString fsError =
    case fsError of
        FsData.NotFound path ->
            "File not found: " ++ path

        FsData.PermissionDenied ->
            "Permission denied"

        FsData.IoError msg ->
            "Unknown error: " ++ msg


{-| Remove this when elm-run provides this functionality.

TODO Also remove the dependency to elm-run/os in Build.addReviewAppDependencies

-}
copyDirectory : { from : String, to : String } -> TTask SpawnError ()
copyDirectory { from, to } =
    Process.run
        "cp"
        { cwd = Nothing
        , env = Nothing
        , args = [ "-R", from, to ]
        , stdin = ProcessData.NullStdin
        , stdout = ProcessData.NullStdout
        , stderr = ProcessData.NullStderr
        }
        |> TTask.map (\_ -> ())

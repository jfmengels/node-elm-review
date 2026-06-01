module Elm.Review.DownloadPackage exposing (download, MissingPkg)

{-| Package cache validation and population.

Checks that all dependencies from elm.json exist in the ELM\_HOME package cache
and downloads missing ones from GitHub.

@docs download, MissingPkg

-}

import Elm.Review.Testable.Fs as Fs
import Elm.Review.Testable.FsData exposing (FsError)
import Elm.Review.Testable.Http as Http
import Elm.Review.Testable.Process as Process
import Elm.Review.Testable.ProcessData as ProcessData exposing (ProcessError)
import Elm.Review.Testable.TTask as TTask exposing (TTask)
import ElmReview.Path as Path exposing (Path)


type CacheError
    = CacheFsError FsError
    | CacheHttpError
    | CacheProcessError ProcessError
    | CacheExtractError String



-- DOWNLOAD


type alias MissingPkg =
    { author : String
    , name : String
    , version : String
    }


{-| Build the GitHub zip URL for a package.
-}
githubZipUrl : MissingPkg -> String
githubZipUrl pkg =
    "https://github.com/" ++ pkg.author ++ "/" ++ pkg.name ++ "/archive/refs/tags/" ++ pkg.version ++ ".zip"


{-| Download a package from GitHub and install it into the cache.
-}
download : Path -> MissingPkg -> TTask CacheError ()
download packagesLocation pkg =
    let
        url : String
        url =
            githubZipUrl pkg

        tmpDir : Path
        tmpDir =
            tempDirLoc packagesLocation pkg

        zipFile : Path
        zipFile =
            Path.join2 tmpDir "package.zip"

        destDir : Path
        destDir =
            Path.join [ packagesLocation, pkg.author, pkg.name, pkg.version ]
    in
    Fs.removeDirectory tmpDir
        |> TTask.onError (\_ -> TTask.succeed ())
        |> TTask.andThen (\() -> Fs.createDirectory tmpDir |> TTask.mapError CacheFsError)
        |> TTask.andThen
            (\() ->
                -- TODO Fetch and writes as Bytes for `elm-run`
                fetchZip url
                    |> TTask.andThen
                        (\zipBytes ->
                            Fs.writeTextFile zipFile zipBytes
                                |> TTask.mapError CacheFsError
                        )
                    |> TTask.andThen (\() -> extractZip tmpDir zipFile)
                    |> TTask.andThen (\() -> findExtractedDir tmpDir)
                    |> TTask.andThen
                        (\sourceDir ->
                            Fs.createDirectory destDir
                                |> TTask.mapError CacheFsError
                                |> TTask.andThen (\() -> installToCache sourceDir destDir)
                        )
                    |> TTask.andThen (\() -> verifySrcDir destDir)
                    |> TTask.andThen
                        (\() ->
                            Fs.removeDirectory tmpDir
                                |> TTask.mapError CacheFsError
                        )
                    |> TTask.onError
                        (\err ->
                            Fs.removeDirectory tmpDir
                                |> TTask.onError (\_ -> TTask.succeed ())
                                |> TTask.andThen (\() -> TTask.fail err)
                        )
            )


fetchZip : String -> TTask CacheError String
fetchZip url =
    Http.get url
        |> TTask.mapError (\_ -> CacheHttpError)


extractZip : Path -> Path -> TTask CacheError ()
extractZip tmpDir zipPath =
    Process.spawn
        "unzip"
        { args = [ "-o", "-q", zipPath, "-d", tmpDir ]
        , cwd = Nothing
        , env = Nothing
        , stdin = ProcessData.NullStdin
        , stdout = ProcessData.NullStdout
        , stderr =
            ProcessData.CaptureStderr
                { maxBytes = 4096
                , onOverflow = ProcessData.TruncateOutput
                }
        }
        |> TTask.andThen Process.wait
        |> TTask.mapError CacheProcessError
        |> TTask.andThen
            (\completed ->
                if completed.exitCode == 0 then
                    TTask.succeed ()

                else
                    TTask.fail (CacheExtractError ("unzip exited with code " ++ String.fromInt completed.exitCode))
            )


{-| GitHub zips extract to a single nested dir like "name-version/".
-}
findExtractedDir : Path -> TTask CacheError String
findExtractedDir tmpDir =
    Fs.list tmpDir
        |> TTask.mapError CacheFsError
        |> TTask.andThen
            (\entries ->
                let
                    dirs =
                        List.filter (\e -> e.isDirectory && e.name /= "__MACOSX") entries
                in
                case dirs of
                    [ single ] ->
                        TTask.succeed (Path.join2 tmpDir single.name)

                    _ ->
                        TTask.succeed tmpDir
            )


installToCache : String -> String -> TTask CacheError ()
installToCache sourceDir destDir =
    Process.spawn
        "sh"
        { args = [ "-c", "cp -a " ++ shellQuote sourceDir ++ "/. " ++ shellQuote destDir ++ "/" ]
        , cwd = Nothing
        , env = Nothing
        , stdin = ProcessData.NullStdin
        , stdout = ProcessData.NullStdout
        , stderr =
            ProcessData.CaptureStderr
                { maxBytes = 4096
                , onOverflow = ProcessData.TruncateOutput
                }
        }
        |> TTask.andThen Process.wait
        |> TTask.mapError CacheProcessError
        |> TTask.andThen
            (\completed ->
                if completed.exitCode == 0 then
                    TTask.succeed ()

                else
                    TTask.fail (CacheExtractError ("cp failed with exit code " ++ String.fromInt completed.exitCode))
            )


shellQuote : String -> String
shellQuote s =
    "'" ++ String.replace "'" "'\\''" s ++ "'"


verifySrcDir : Path -> TTask CacheError ()
verifySrcDir destDir =
    Fs.list (Path.join2 destDir "src")
        |> TTask.mapError CacheFsError
        |> TTask.andThen
            (\entries ->
                if List.isEmpty entries then
                    TTask.fail (CacheExtractError "package has no src/ directory after installation")

                else
                    TTask.succeed ()
            )



-- PATHS


tempDirLoc : Path -> MissingPkg -> Path
tempDirLoc packagesLocation pkg =
    Path.join2 packagesLocation (".elm-cache-" ++ pkg.author ++ "-" ++ pkg.name ++ "-" ++ pkg.version)

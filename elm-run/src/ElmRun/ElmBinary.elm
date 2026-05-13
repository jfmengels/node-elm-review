module ElmRun.ElmBinary exposing (findElmVersion)

import Elm.Review.Testable.Process as Process
import Elm.Review.Testable.ProcessData as ProcessData
import Elm.Review.Testable.TTask as TTask exposing (TTask)
import Elm.Version exposing (Version)


findElmVersion : TTask x Version
findElmVersion =
    Process.run
        -- TODO Use elmCompilerPath if available
        "elm"
        { cwd = Nothing
        , env = Nothing
        , args = [ "--version" ]
        , stdin = ProcessData.NullStdin
        , stdout = ProcessData.CaptureStdout { maxBytes = 4096, onOverflow = ProcessData.TruncateOutput }
        , stderr = ProcessData.NullStderr
        }
        |> TTask.map .stdout
        |> TTask.onError (\_ -> TTask.succeed Nothing)
        |> TTask.map
            (\stdout ->
                let
                    version : Maybe Version
                    version =
                        Maybe.andThen
                            (\str ->
                                Elm.Version.fromString (String.trim str)
                            )
                            stdout
                in
                case version of
                    Just v ->
                        v

                    Nothing ->
                        defaultElmVersion ()
            )


defaultElmVersion : () -> Version
defaultElmVersion () =
    case Elm.Version.fromString "0.19.1" of
        Just v ->
            v

        Nothing ->
            defaultElmVersion ()

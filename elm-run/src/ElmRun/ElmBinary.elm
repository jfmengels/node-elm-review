module ElmRun.ElmBinary exposing (findElmVersion)

import Elm.Version exposing (Version)
import ElmRun.ProcessExtra as ProcessExtra
import Os exposing (ProcessCapability)
import Os.Process as Process exposing (ProcessError)
import Task exposing (Task)


findElmVersion : ProcessCapability -> Task x Version
findElmVersion os =
    ProcessExtra.runButFailOnError os
        -- TODO Use elmCompilerPath if available
        "elm"
        { cwd = Nothing
        , env = Nothing
        , args = [ "--version" ]
        , stdin = Process.NullStdin
        , stdout = Process.CaptureStdout { maxBytes = 4096, onOverflow = Process.TruncateOutput }
        , stderr = Process.NullStderr
        }
        |> Task.map .stdout
        |> Task.onError (\_ -> Task.succeed Nothing)
        |> Task.map
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

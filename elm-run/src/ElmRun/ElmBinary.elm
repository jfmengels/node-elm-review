module ElmRun.ElmBinary exposing (findElmVersion)

import Elm.Version exposing (Version)
import ElmRun.OsExtra as OsExtra
import Os exposing (ProcessCapability)
import Os.Process as Process exposing (ProcessError)
import Task exposing (Task)


findElmVersion : ProcessCapability -> Task x Version
findElmVersion os =
    OsExtra.which os "elm"
        |> Task.andThen
            (\maybeElmBinary ->
                case maybeElmBinary of
                    Just elmBinary ->
                        getVersion os elmBinary

                    Nothing ->
                        Task.succeed Nothing
            )
        |> Task.onError (\_ -> Task.succeed Nothing)
        |> Task.map
            (\version ->
                case version of
                    Just v ->
                        v

                    Nothing ->
                        defaultElmVersion ()
            )


{-| Find the path to a command.
-}
getVersion : ProcessCapability -> String -> Task ProcessError (Maybe Version)
getVersion os elmBinary =
    Process.run os
        elmBinary
        { cwd = Nothing
        , env = Nothing
        , args = [ "--version" ]
        , stdin = Process.NullStdin
        , stdout = Process.CaptureStdout { maxBytes = 4096, onOverflow = Process.TruncateOutput }
        , stderr = Process.NullStderr
        }
        |> Task.map
            (\result ->
                Maybe.andThen
                    (\stdout ->
                        Elm.Version.fromString (String.trim stdout)
                    )
                    result.stdout
            )


defaultElmVersion : () -> Version
defaultElmVersion () =
    case Elm.Version.fromString "0.19.1" of
        Just v ->
            v

        Nothing ->
            defaultElmVersion ()

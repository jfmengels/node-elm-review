module Wrapper.Build exposing (..)

import Fs exposing (FileSystem, FsError)
import Task
import Wrapper.Color exposing (Color(..))
import Wrapper.Options as Options exposing (Options)
import Wrapper.Problem as Problem exposing (Problem)


type Msg
    = ReceivedElmJson (Result Problem String)


build : FileSystem -> Options -> Cmd Msg
build fs options =
    case options.reviewProject of
        Options.Local reviewFolder ->
            buildLocalProject fs options reviewFolder

        Options.Remote remoteTemplate ->
            Debug.todo "Build remote template"


buildLocalProject : FileSystem -> Options -> String -> Cmd Msg
buildLocalProject fs options reviewFolder =
    let
        elmJsonPath : String
        elmJsonPath =
            -- TODO Use path functions
            String.join "/" [ reviewFolder, "elm.json" ]
    in
    Fs.readTextFile fs elmJsonPath
        |> Task.mapError
            (\error ->
                case error of
                    Fs.NotFound _ ->
                        { title = "INCORRECT CONFIGURATION"
                        , message =
                            \c ->
                                "I could not find a review configuration. I was expecting to find an " ++ c Yellow "elm.json" ++ " file and a " ++ c Cyan "ReviewConfig.elm" ++ " file in " ++ c Cyan (reviewFolder ++ "/") ++ """

I can help set you up with an initial configuration if you run """ ++ c Magenta "elm-review init" ++ "."
                        }
                            |> Problem.from
                            |> Problem.withPath elmJsonPath

                    Fs.PermissionDenied ->
                        { title = "PERMISSION DENIED"
                        , message =
                            \c ->
                                "I tried reading " ++ c Yellow elmJsonPath ++ """ but couldn't because of the file's read permissions.

Try changing the permissions of the file and/or its parents directories."""
                        }
                            |> Problem.from
                            |> Problem.withPath elmJsonPath

                    Fs.IoError string ->
                        Debug.todo ("Unknown error: " ++ string)
            )
        |> Task.attempt ReceivedElmJson

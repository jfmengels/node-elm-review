module Elm.Review.FileFetch exposing
    ( Model(..)
    , Msg
    , init
    , isReady
    , update
    )

import Cli exposing (Env)
import Elm.Docs
import Elm.Package
import Elm.Project
import Elm.Review.SuppressedErrors as SuppressedErrors exposing (SuppressedErrors)
import Elm.Version
import Fs exposing (FileSystem, FsError(..))
import Json.Decode as Decode
import Review.Project as Project exposing (Project)
import Review.Project.Dependency as Dependency exposing (Dependency)
import Task
import Worker.Capabilities exposing (Console)


type Model
    = Model PendingTaskCount


type alias PendingTaskCount =
    Int


init : { fs : FileSystem, suppress : Bool, suppressionFolder : String } -> ( Model, Cmd Msg )
init { fs, suppress, suppressionFolder } =
    let
        tasks : List (Cmd Msg)
        tasks =
            List.filterMap
                identity
                [ Just (fetchElmJson fs)
                , Just (fetchReadme fs)
                , if suppress then
                    Nothing

                  else
                    Just (fetchSuppressionFiles fs suppressionFolder)
                ]
    in
    ( Model (List.length tasks)
    , Cmd.batch tasks
    )


isReady : Model -> Bool
isReady (Model pendingTaskCount) =
    pendingTaskCount == 0


type Msg
    = ReceivedElmJson String (Result Fs.FsError String)
    | ReceivedReadme String (Result Fs.FsError String)
    | ReceivedDependency String (Result Fs.FsError { elmJson : String, docsJson : String })
    | ReceivedElmFileList String (Result Fs.FsError ( List String, List ( String, Fs.FsError ) ))
    | ReceivedElmFile String (Result Fs.FsError String)
    | ReceivedSuppressedErrorsList String (Result Fs.FsError ( List String, List ( String, Fs.FsError ) ))
    | ReceivedSuppressedErrorsFile String (Result Fs.FsError String)


type alias UpdateInput =
    { msg : Msg
    , fs : FileSystem
    , stderr : Console
    , fileFetch : Model
    , project : Project
    , suppressedErrors : SuppressedErrors
    , ignoreProblematicDependencies : Bool
    , abortWithDetails : { title : String, message : String } -> Cmd Msg
    }


type alias UpdateOutput =
    { fileFetch : Model
    , project : Project
    , suppressedErrors : SuppressedErrors
    , cmd : Cmd Msg
    }


update : UpdateInput -> UpdateOutput
update { msg, fs, stderr, fileFetch, project, suppressedErrors, ignoreProblematicDependencies, abortWithDetails } =
    let
        (Model pendingTaskCount) =
            fileFetch

        decrementTaskCount : () -> UpdateOutput
        decrementTaskCount () =
            { fileFetch = toModel (pendingTaskCount - 1)
            , project = project
            , suppressedErrors = suppressedErrors
            , cmd = Cmd.none
            }
    in
    case msg of
        ReceivedElmJson path (Ok rawElmJson) ->
            case Decode.decodeString Elm.Project.decoder rawElmJson of
                Ok elmJson ->
                    let
                        sourceDirectories : List String
                        sourceDirectories =
                            case elmJson of
                                Elm.Project.Application application ->
                                    "test" :: application.dirs

                                Elm.Project.Package _ ->
                                    [ "src", "test" ]

                        elmHomePath : String
                        elmHomePath =
                            --TODO Get from somewhere
                            "/Users/m1/.elm/"

                        dependencies : List ( String, String )
                        dependencies =
                            case elmJson of
                                Elm.Project.Application application ->
                                    -- TODO Optimize
                                    let
                                        toStrings : ( Elm.Package.Name, Elm.Version.Version ) -> ( String, String )
                                        toStrings ( name, version ) =
                                            ( Elm.Package.toString name, Elm.Version.toString version )
                                    in
                                    List.concat
                                        [ List.map toStrings application.depsDirect
                                        , List.map toStrings application.depsIndirect
                                        , List.map toStrings application.testDepsDirect
                                        , List.map toStrings application.testDepsIndirect
                                        ]

                                Elm.Project.Package _ ->
                                    -- TODO Handle package deps
                                    []
                    in
                    { fileFetch = toModel (pendingTaskCount + List.length sourceDirectories + List.length dependencies - 1)
                    , project = Project.addElmJson { path = path, raw = rawElmJson, project = elmJson } project
                    , suppressedErrors = suppressedErrors
                    , cmd =
                        List.map (fetchElmFiles fs) sourceDirectories
                            ++ List.map (\( name, version ) -> fetchDependency fs elmHomePath name version) dependencies
                            |> Cmd.batch
                    }

                Err _ ->
                    decrementTaskCount ()

        ReceivedElmJson _ (Err err) ->
            { fileFetch = toModel (pendingTaskCount - 1)
            , project = project
            , suppressedErrors = suppressedErrors
            , cmd =
                Cmd.batch
                    [ Cli.println stderr (errorToString err)
                    , Cli.exit 1
                    ]
            }

        ReceivedReadme path result ->
            case result of
                Ok content ->
                    { fileFetch = toModel (pendingTaskCount - 1)
                    , project = Project.addReadme { path = path, content = content } project
                    , suppressedErrors = suppressedErrors
                    , cmd = Cmd.none
                    }

                Err _ ->
                    decrementTaskCount ()

        ReceivedDependency packageName result ->
            case result of
                Ok { elmJson, docsJson } ->
                    case
                        Result.map2 (Dependency.create packageName)
                            (Decode.decodeString Elm.Project.decoder elmJson)
                            (Decode.decodeString (Decode.list Elm.Docs.decoder) docsJson)
                    of
                        Ok dependency ->
                            { fileFetch = toModel (pendingTaskCount - 1)
                            , project = Project.addDependency dependency project
                            , suppressedErrors = suppressedErrors
                            , cmd = Cmd.none
                            }

                        Err decodeError ->
                            if ignoreProblematicDependencies then
                                decrementTaskCount ()

                            else
                                { fileFetch = toModel (pendingTaskCount - 1)
                                , project = project
                                , suppressedErrors = suppressedErrors
                                , cmd =
                                    if String.contains "I need a valid module name like" (Decode.errorToString decodeError) then
                                        abortWithDetails
                                            { title = "FOUND PROBLEMATIC DEPENDENCIES"
                                            , message =
                                                """I encountered an error when reading the dependencies of the project. It seems due to dependencies with modules containing `_` in their names. Unfortunately, this is an error I have no control over and I am waiting in one of the libraries I depend on. What I propose you do, is to re-run elm-review like this:

    elm-review --ignore-problematic-dependencies

This will ignore the problematic dependencies, and can GIVE YOU INCORRECT RESULTS! This is a temporary measure.

If I am mistaken about the nature of the problem, please open a bug report at https://github.com/jfmengels/node-elm-review/issues:

"""
                                                    ++ Decode.errorToString decodeError
                                            }

                                    else
                                        abortWithDetails
                                            { title = "PROBLEM READING DEPENDENCIES"
                                            , message =
                                                "I encountered an error when reading the dependencies of the project. I suggest opening a bug report at https://github.com/jfmengels/node-elm-review/issues."
                                                    ++ Decode.errorToString decodeError
                                            }
                                }

                Err _ ->
                    -- TODO Download dependencies
                    decrementTaskCount ()

        ReceivedElmFileList directory result ->
            case result of
                Ok ( files, _ ) ->
                    { fileFetch = toModel (pendingTaskCount + List.length files - 1)
                    , project = project
                    , suppressedErrors = suppressedErrors
                    , cmd =
                        List.map (\filePath -> fetchElmFile fs (joinPaths directory filePath)) files
                            |> Cmd.batch
                    }

                Err err ->
                    { fileFetch = toModel (pendingTaskCount - 1)
                    , project = project
                    , suppressedErrors = suppressedErrors

                    -- TODO Exit?
                    , cmd = Cli.println stderr (errorToString err)
                    }

        ReceivedSuppressedErrorsList directory result ->
            case result of
                Ok ( files, _ ) ->
                    { fileFetch = toModel (pendingTaskCount + List.length files - 1)
                    , project = project
                    , suppressedErrors = suppressedErrors
                    , cmd =
                        List.map
                            (\filePath ->
                                Fs.readTextFile fs (directory ++ "/" ++ filePath)
                                    |> Task.attempt (ReceivedSuppressedErrorsFile filePath)
                            )
                            files
                            |> Cmd.batch
                    }

                Err (Fs.NotFound _) ->
                    decrementTaskCount ()

                Err _ ->
                    -- TODO Exit?
                    decrementTaskCount ()

        ReceivedElmFile path result ->
            case result of
                Ok source ->
                    { fileFetch = toModel (pendingTaskCount - 1)
                    , project = Project.addModule { path = path, source = source } project
                    , suppressedErrors = suppressedErrors
                    , cmd = Cmd.none
                    }

                Err err ->
                    { fileFetch = toModel (pendingTaskCount - 1)
                    , project = project
                    , suppressedErrors = suppressedErrors

                    -- TODO Exit?
                    , cmd = Cli.println stderr ("FileRead error: " ++ path ++ " - " ++ errorToString err)
                    }

        ReceivedSuppressedErrorsFile path result ->
            case result of
                Ok contents ->
                    let
                        ruleName : String
                        ruleName =
                            -- Remove leading "./" and trailing ".json"
                            String.slice 2 -5 path
                    in
                    { fileFetch = toModel (pendingTaskCount - 1)
                    , project = project
                    , suppressedErrors = SuppressedErrors.addFromFile ruleName contents suppressedErrors
                    , cmd = Cmd.none
                    }

                Err err ->
                    { fileFetch = toModel (pendingTaskCount - 1)
                    , project = project
                    , suppressedErrors = suppressedErrors

                    -- TODO Exit?
                    , cmd = Cli.println stderr ("FileRead error: " ++ path ++ " - " ++ errorToString err)
                    }


toModel : PendingTaskCount -> Model
toModel pendingTaskCount =
    Model (Basics.max 0 pendingTaskCount)


fetchElmFile : FileSystem -> String -> Cmd Msg
fetchElmFile fs filePath =
    Fs.readTextFile fs filePath
        |> Task.attempt (ReceivedElmFile filePath)


fetchElmJson : FileSystem -> Cmd Msg
fetchElmJson fs =
    readTextFile fs ReceivedElmJson "elm.json"


fetchReadme : FileSystem -> Cmd Msg
fetchReadme fs =
    readTextFile fs ReceivedReadme "README.md"


fetchSuppressionFiles : FileSystem -> String -> Cmd Msg
fetchSuppressionFiles fs directory =
    Fs.walkTree fs directory (Just "*.json") Fs.Any
        |> Task.attempt (ReceivedSuppressedErrorsList directory)


fetchElmFiles : FileSystem -> String -> Cmd Msg
fetchElmFiles fs directory =
    Fs.walkTree fs directory (Just "*.elm") Fs.Any
        |> Task.attempt (ReceivedElmFileList directory)


fetchDependency : FileSystem -> String -> String -> String -> Cmd Msg
fetchDependency fs elmHomePath packageName packageVersion =
    let
        -- TODO Get from somewhere
        elmVersion : String
        elmVersion =
            "0.19.1"

        directory : String
        directory =
            -- TODO Use path functions
            String.join "/" [ elmHomePath, elmVersion, "packages", packageName, packageVersion ]
    in
    Task.map2 (\elmJson docsJson -> { elmJson = elmJson, docsJson = docsJson })
        (Fs.readTextFile fs (directory ++ "/elm.json"))
        (Fs.readTextFile fs (directory ++ "/docs.json"))
        |> Task.attempt (ReceivedDependency packageName)


readTextFile : FileSystem -> (String -> Result FsError String -> msg) -> String -> Cmd msg
readTextFile fs toMsg path =
    Fs.readTextFile fs path
        |> Task.attempt (\result -> toMsg path result)


joinPaths : String -> String -> String
joinPaths directory filePath =
    directory ++ String.dropLeft 1 filePath ++ ""


errorToString : FsError -> String
errorToString fsError =
    case fsError of
        NotFound path ->
            "File not found: " ++ path

        PermissionDenied ->
            "Permission denied"

        IoError msg ->
            "Unknown error: " ++ msg

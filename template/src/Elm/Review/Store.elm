module Elm.Review.Store exposing
    ( Model
    , Msg
    , hasPendingTasks
    , init
    , project
    , suppressedErrors
    , update
    )

import Cli exposing (Env)
import Elm.Docs
import Elm.Package
import Elm.Project
import Elm.Review.RunEnvironment as RunEnvironment exposing (RunEnvironment)
import Elm.Review.SuppressedErrors as SuppressedErrors exposing (SuppressedErrors)
import Elm.Version
import Fs exposing (FileSystem, FsError(..))
import Json.Decode as Decode
import Review.Project as Project exposing (Project)
import Review.Project.Dependency as Dependency exposing (Dependency)
import Task
import Worker.Capabilities exposing (Console)


type Model
    = Model ModelData


type alias ModelData =
    { pendingTaskCount : PendingTaskCount
    , project : Project
    , suppressedErrors : SuppressedErrors
    }


type alias PendingTaskCount =
    Int


init : { fs : FileSystem, suppress : Bool, runEnvironment : RunEnvironment } -> ( Model, Cmd Msg )
init { fs, suppress, runEnvironment } =
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
                    Just (fetchSuppressionFiles fs (RunEnvironment.suppressionFolder runEnvironment))
                ]
    in
    ( Model
        { pendingTaskCount = List.length tasks
        , project = Project.new
        , suppressedErrors = SuppressedErrors.empty
        }
    , Cmd.batch tasks
    )


hasPendingTasks : Model -> Bool
hasPendingTasks (Model { pendingTaskCount }) =
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
    , runEnvironment : RunEnvironment
    , stderr : Console
    , ignoreProblematicDependencies : Bool
    , abortWithDetails : { title : String, message : String } -> Cmd Msg
    }


type alias UpdateOutput =
    { fileFetch : Model
    , suppressedErrors : SuppressedErrors
    , cmd : Cmd Msg
    }


update : UpdateInput -> Model -> ( Model, Cmd Msg )
update inputs (Model model) =
    updateInner inputs model
        |> Tuple.mapFirst Model


updateInner : UpdateInput -> ModelData -> ( ModelData, Cmd Msg )
updateInner { msg, fs, runEnvironment, stderr, ignoreProblematicDependencies, abortWithDetails } model =
    let
        decrementTaskCount : () -> ( ModelData, Cmd Msg )
        decrementTaskCount () =
            ( { pendingTaskCount = minimum (model.pendingTaskCount - 1)
              , project = model.project
              , suppressedErrors = model.suppressedErrors
              }
            , Cmd.none
            )
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

                        addDeps : List ( Elm.Package.Name, Elm.Version.Version ) -> List (Cmd Msg) -> List (Cmd Msg)
                        addDeps deps initial =
                            List.foldl
                                (\( name, version ) acc ->
                                    fetchDependency fs runEnvironment (Elm.Package.toString name) (Elm.Version.toString version) :: acc
                                )
                                initial
                                deps

                        addDependencies : List (Cmd Msg) -> List (Cmd Msg)
                        addDependencies initial =
                            case elmJson of
                                Elm.Project.Application application ->
                                    initial
                                        |> addDeps application.depsDirect
                                        |> addDeps application.depsIndirect
                                        |> addDeps application.testDepsDirect
                                        |> addDeps application.testDepsIndirect

                                Elm.Project.Package _ ->
                                    Debug.todo "Handle package deps"

                        tasks : List (Cmd Msg)
                        tasks =
                            List.map (fetchElmFiles fs) sourceDirectories
                                |> addDependencies
                    in
                    ( { pendingTaskCount = minimum (model.pendingTaskCount + List.length tasks - 1)
                      , project = Project.addElmJson { path = path, raw = rawElmJson, project = elmJson } model.project
                      , suppressedErrors = model.suppressedErrors
                      }
                    , Cmd.batch tasks
                    )

                Err _ ->
                    decrementTaskCount ()

        ReceivedElmJson _ (Err err) ->
            ( { pendingTaskCount = minimum (model.pendingTaskCount - 1)
              , project = model.project
              , suppressedErrors = model.suppressedErrors
              }
            , Cmd.batch
                [ Cli.println stderr (errorToString err)
                , Cli.exit 1
                ]
            )

        ReceivedReadme path result ->
            case result of
                Ok content ->
                    ( { pendingTaskCount = minimum (model.pendingTaskCount - 1)
                      , project = Project.addReadme { path = path, content = content } model.project
                      , suppressedErrors = model.suppressedErrors
                      }
                    , Cmd.none
                    )

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
                            ( { pendingTaskCount = minimum (model.pendingTaskCount - 1)
                              , project = Project.addDependency dependency model.project
                              , suppressedErrors = model.suppressedErrors
                              }
                            , Cmd.none
                            )

                        Err decodeError ->
                            if ignoreProblematicDependencies then
                                decrementTaskCount ()

                            else
                                ( { pendingTaskCount = minimum (model.pendingTaskCount - 1)
                                  , project = model.project
                                  , suppressedErrors = model.suppressedErrors
                                  }
                                , if String.contains "I need a valid module name like" (Decode.errorToString decodeError) then
                                    abortWithDetails
                                        { title = "FOUND PROBLEMATIC DEPENDENCIES"
                                        , message =
                                            """I encountered an error when reading the dependencies of the project. It seems due to dependencies with modules containing `_` in their names. Unfortunately, this is an error I have no control over and I am waiting in one of the libraries I depend on. What I propose you do, is to re-run elm-review like this:

    elm-review --ignore-problematic-dependencies

This will ignore the problematic dependencies, and can GIVE YOU INCORRECT RESULTS! This is a temporary measure.

If I am mistaken about the nature of problem, please open a bug report at https://github.com/jfmengels/node-elm-review/issues:

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
                                )

                Err _ ->
                    -- TODO Download dependencies
                    decrementTaskCount ()

        ReceivedElmFileList directory result ->
            case result of
                Ok ( files, _ ) ->
                    ( { pendingTaskCount = minimum (model.pendingTaskCount + List.length files - 1)
                      , project = model.project
                      , suppressedErrors = model.suppressedErrors
                      }
                    , List.map (\filePath -> fetchElmFile fs (joinPaths directory filePath)) files
                        |> Cmd.batch
                    )

                Err (Fs.NotFound _) ->
                    decrementTaskCount ()

                Err err ->
                    ( { pendingTaskCount = minimum (model.pendingTaskCount - 1)
                      , project = model.project
                      , suppressedErrors = model.suppressedErrors
                      }
                      -- TODO Exit?
                    , Cli.println stderr (errorToString err)
                    )

        ReceivedElmFile path result ->
            case result of
                Ok source ->
                    ( { pendingTaskCount = minimum (model.pendingTaskCount - 1)
                      , project = Project.addModule { path = path, source = source } model.project
                      , suppressedErrors = model.suppressedErrors
                      }
                    , Cmd.none
                    )

                Err err ->
                    ( { pendingTaskCount = minimum (model.pendingTaskCount - 1)
                      , project = model.project
                      , suppressedErrors = model.suppressedErrors
                      }
                    , -- TODO Exit?
                      Cli.println stderr ("FileRead error: " ++ path ++ " - " ++ errorToString err)
                    )

        ReceivedSuppressedErrorsList directory result ->
            case result of
                Ok ( files, _ ) ->
                    ( { pendingTaskCount = minimum (model.pendingTaskCount + List.length files - 1)
                      , project = model.project
                      , suppressedErrors = model.suppressedErrors
                      }
                    , List.map
                        (\filePath ->
                            Fs.readTextFile fs (directory ++ "/" ++ filePath)
                                |> Task.attempt (ReceivedSuppressedErrorsFile filePath)
                        )
                        files
                        |> Cmd.batch
                    )

                Err (Fs.NotFound _) ->
                    decrementTaskCount ()

                Err _ ->
                    -- TODO Exit?
                    decrementTaskCount ()

        ReceivedSuppressedErrorsFile path result ->
            case result of
                Ok contents ->
                    let
                        ruleName : String
                        ruleName =
                            -- Remove leading "./" and trailing ".json"
                            String.slice 2 -5 path
                    in
                    ( { pendingTaskCount = minimum (model.pendingTaskCount - 1)
                      , project = model.project
                      , suppressedErrors = SuppressedErrors.addFromFile ruleName contents model.suppressedErrors
                      }
                    , Cmd.none
                    )

                Err err ->
                    ( { pendingTaskCount = minimum (model.pendingTaskCount - 1)
                      , project = model.project
                      , suppressedErrors = model.suppressedErrors
                      }
                      -- TODO Exit?
                    , Cli.println stderr ("FileRead error: " ++ path ++ " - " ++ errorToString err)
                    )


minimum : Int -> Int
minimum =
    Basics.max 0


project : Model -> Project
project (Model model) =
    model.project


suppressedErrors : Model -> SuppressedErrors
suppressedErrors (Model model) =
    model.suppressedErrors


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


fetchDependency : FileSystem -> RunEnvironment -> String -> String -> Cmd Msg
fetchDependency fs runEnvironment packageName packageVersion =
    let
        directory : String
        directory =
            -- TODO Use path functions
            String.join "/" [ runEnvironment.elmHomePath, runEnvironment.elmVersion, "packages", packageName, packageVersion ]
    in
    Task.map2 (\elmJson docsJson -> { elmJson = elmJson, docsJson = docsJson })
        -- TODO Use path functions
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

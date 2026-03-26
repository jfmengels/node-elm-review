module Elm.Review.Store exposing
    ( Model, init
    , Msg, update, UpdateInput
    , hasPendingTasks
    , project, setProject, updateProject
    , suppressedErrors, setSuppressedErrors
    , ruleLinks
    )

{-|

@docs Model, init
@docs Msg, update, UpdateInput
@docs hasPendingTasks
@docs project, setProject, updateProject
@docs suppressedErrors, setSuppressedErrors
@docs ruleLinks

-}

import Cli
import Dict exposing (Dict)
import Elm.Docs
import Elm.Module
import Elm.Package
import Elm.Project
import Elm.Review.RunEnvironment as RunEnvironment exposing (RunEnvironment)
import Elm.Review.SuppressedErrors as SuppressedErrors exposing (SuppressedErrors)
import Elm.Version
import Fs exposing (FileSystem, FsError(..))
import Json.Decode as Decode
import Review.Project as Project exposing (Project)
import Review.Project.Dependency as Dependency
import Task exposing (Task)
import Worker.Capabilities exposing (Console)


type Model
    = Model ModelData


type alias ModelData =
    { pendingTaskCount : PendingTaskCount
    , project : Project
    , suppressedErrors : SuppressedErrors
    , ruleLinks : Dict String String
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
                , Just (fetchRuleLinks fs runEnvironment)
                ]
    in
    ( Model
        { pendingTaskCount = List.length tasks
        , project = Project.new
        , suppressedErrors = SuppressedErrors.empty
        , ruleLinks = Dict.empty
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
    | ReceivedRuleLinks { links : Dict String String, fromCache : Bool }


type alias UpdateInput =
    { fs : FileSystem
    , runEnvironment : RunEnvironment
    , stderr : Console
    , ignoreProblematicDependencies : Bool
    , abortWithDetails : { title : String, message : String } -> Cmd Msg
    }


update : UpdateInput -> Msg -> Model -> ( Model, Cmd Msg )
update inputs msg (Model model) =
    updateInner inputs msg model
        |> Tuple.mapFirst Model


updateInner : UpdateInput -> Msg -> ModelData -> ( ModelData, Cmd Msg )
updateInner { fs, runEnvironment, stderr, ignoreProblematicDependencies, abortWithDetails } msg model =
    let
        decrementTaskCount : () -> ( ModelData, Cmd Msg )
        decrementTaskCount () =
            ( { pendingTaskCount = minimum (model.pendingTaskCount - 1)
              , project = model.project
              , suppressedErrors = model.suppressedErrors
              , ruleLinks = model.ruleLinks
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
                      , ruleLinks = model.ruleLinks
                      }
                    , Cmd.batch tasks
                    )

                Err _ ->
                    decrementTaskCount ()

        ReceivedElmJson _ (Err err) ->
            ( { pendingTaskCount = minimum (model.pendingTaskCount - 1)
              , project = model.project
              , suppressedErrors = model.suppressedErrors
              , ruleLinks = model.ruleLinks
              }
            , Cmd.batch
                [ Cli.println stderr ("elm.json - " ++ errorToString err)
                , Cli.exit 1
                ]
            )

        ReceivedReadme path result ->
            case result of
                Ok content ->
                    ( { pendingTaskCount = minimum (model.pendingTaskCount - 1)
                      , project = Project.addReadme { path = path, content = content } model.project
                      , suppressedErrors = model.suppressedErrors
                      , ruleLinks = model.ruleLinks
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
                              , ruleLinks = model.ruleLinks
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
                                  , ruleLinks = model.ruleLinks
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
                      , ruleLinks = model.ruleLinks
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
                      , ruleLinks = model.ruleLinks
                      }
                      -- TODO Exit?
                    , Cli.println stderr (directory ++ " - " ++ errorToString err)
                    )

        ReceivedElmFile path result ->
            case result of
                Ok source ->
                    ( { pendingTaskCount = minimum (model.pendingTaskCount - 1)
                      , project = Project.addModule { path = path, source = source } model.project
                      , suppressedErrors = model.suppressedErrors
                      , ruleLinks = model.ruleLinks
                      }
                    , Cmd.none
                    )

                Err err ->
                    ( { pendingTaskCount = minimum (model.pendingTaskCount - 1)
                      , project = model.project
                      , suppressedErrors = model.suppressedErrors
                      , ruleLinks = model.ruleLinks
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
                      , ruleLinks = model.ruleLinks
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
                      , ruleLinks = model.ruleLinks
                      }
                    , Cmd.none
                    )

                Err err ->
                    ( { pendingTaskCount = minimum (model.pendingTaskCount - 1)
                      , project = model.project
                      , suppressedErrors = model.suppressedErrors
                      , ruleLinks = model.ruleLinks
                      }
                      -- TODO Exit?
                    , Cli.println stderr ("FileRead error: " ++ path ++ " - " ++ errorToString err)
                    )

        ReceivedRuleLinks { links, fromCache } ->
            ( { pendingTaskCount = minimum (model.pendingTaskCount - 1)
              , project = model.project
              , suppressedErrors = model.suppressedErrors
              , ruleLinks = links
              }
            , Cmd.none
            )


minimum : Int -> Int
minimum =
    Basics.max 0


project : Model -> Project
project (Model model) =
    model.project


setProject : Project -> Model -> Model
setProject newProject (Model model) =
    Model
        { pendingTaskCount = model.pendingTaskCount
        , project = newProject
        , suppressedErrors = model.suppressedErrors
        , ruleLinks = model.ruleLinks
        }


updateProject : (Project -> Project) -> Model -> Model
updateProject updateFn (Model model) =
    Model
        { pendingTaskCount = model.pendingTaskCount
        , project = updateFn model.project
        , suppressedErrors = model.suppressedErrors
        , ruleLinks = model.ruleLinks
        }


suppressedErrors : Model -> SuppressedErrors
suppressedErrors (Model model) =
    model.suppressedErrors


setSuppressedErrors : SuppressedErrors -> Model -> Model
setSuppressedErrors newSuppressedErrors (Model model) =
    Model
        { pendingTaskCount = model.pendingTaskCount
        , project = model.project
        , suppressedErrors = newSuppressedErrors
        , ruleLinks = model.ruleLinks
        }


ruleLinks : Model -> Dict String String
ruleLinks (Model model) =
    model.ruleLinks


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


fetchRuleLinks : FileSystem -> RunEnvironment -> Cmd Msg
fetchRuleLinks fs runEnvironment =
    -- TODO Use path functions
    Fs.readTextFile fs (runEnvironment.reviewFolder ++ "/elm.json")
        |> Task.andThen
            (\elmJson ->
                case Decode.decodeString Elm.Project.decoder elmJson of
                    Ok (Elm.Project.Application { depsDirect, depsIndirect }) ->
                        let
                            packagesDirectory : String
                            packagesDirectory =
                                -- TODO Use path functions
                                String.join "/" [ runEnvironment.elmHomePath, runEnvironment.elmVersion, "packages" ]
                        in
                        (depsDirect ++ depsIndirect)
                            |> List.map (readElmJson fs packagesDirectory)
                            |> Task.sequence
                            |> Task.map (List.concat >> Dict.fromList)

                    _ ->
                        Task.succeed Dict.empty
            )
        |> Task.onError (\_ -> Task.succeed Dict.empty)
        |> Task.perform (\links -> ReceivedRuleLinks { links = links, fromCache = False })


readElmJson : FileSystem -> String -> ( Elm.Package.Name, Elm.Version.Version ) -> Task x (List ( String, String ))
readElmJson fs packagesDirectory ( rawPackageName, rawPackageVersion ) =
    let
        packageName : String
        packageName =
            Elm.Package.toString rawPackageName

        packageVersion : String
        packageVersion =
            Elm.Version.toString rawPackageVersion
    in
    -- TODO Use path functions
    String.join "/" [ packagesDirectory, packageName, packageVersion, "elm.json" ]
        |> Fs.readTextFile fs
        |> Task.map
            (\elmJson ->
                case Decode.decodeString Elm.Project.decoder elmJson of
                    Ok (Elm.Project.Package package) ->
                        if packageDependsOnElmReview package.deps then
                            moduleLinks packageName packageVersion package

                        else
                            []

                    _ ->
                        []
            )
        |> Task.onError (\_ -> Task.succeed [])


packageDependsOnElmReview : Elm.Project.Deps version -> Bool
packageDependsOnElmReview deps =
    List.any (\( pkgName, _ ) -> Elm.Package.toString pkgName == "jfmengels/elm-review") deps


moduleLinks : String -> String -> Elm.Project.PackageInfo -> List ( String, String )
moduleLinks packageName packageVersion package =
    case package.exposed of
        Elm.Project.ExposedList names ->
            List.map (linkToModule packageName packageVersion) names

        Elm.Project.ExposedDict list ->
            List.concatMap Tuple.second list |> List.map (linkToModule packageName packageVersion)


linkToModule : String -> String -> Elm.Module.Name -> ( String, String )
linkToModule dependencyName packageVersion rawModuleName =
    let
        moduleName : String
        moduleName =
            Elm.Module.toString rawModuleName
    in
    ( moduleName, "https://package.elm-lang.org/packages/" ++ dependencyName ++ "/" ++ packageVersion ++ "/" ++ String.replace "." "-" moduleName )


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

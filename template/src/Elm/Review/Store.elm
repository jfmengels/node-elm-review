module Elm.Review.Store exposing
    ( Model, init
    , Msg, update, UpdateInput
    , applyChangesFromFix
    , subscriptions
    , Readiness(..), checkReadiness
    , project, setProject
    , suppressedErrors, setSuppressedErrors
    , ruleLinks
    )

{-|

@docs Model, init
@docs Msg, update, UpdateInput
@docs applyChangesFromFix
@docs subscriptions
@docs Readiness, checkReadiness
@docs project, setProject
@docs suppressedErrors, setSuppressedErrors
@docs ruleLinks

-}

import Dict exposing (Dict)
import Elm.Constraint
import Elm.Docs
import Elm.Module
import Elm.Package
import Elm.Project
import Elm.Review.Options exposing (Options)
import Elm.Review.StoreVersion as StoreVersion exposing (StoreVersion)
import Elm.Review.SuppressedErrors as SuppressedErrors exposing (SuppressedErrors)
import Elm.Version
import ElmReview.Color exposing (Color(..))
import ElmReview.Path as Path exposing (Path)
import ElmReview.Problem as Problem exposing (Problem, ProblemSimple)
import ElmRun.FsExtra as FsExtra
import ElmRun.TaskExtra as FsExtra
import Fs exposing (FileSystem, FsError(..))
import Json.Decode as Decode
import Review.Project as Project exposing (Project)
import Review.Project.Dependency as Dependency
import Task exposing (Task)
import Worker.Capabilities exposing (Console, FileWatcher)
import Worker.FileWatcher as FileWatcher exposing (FileEvent)


type Model
    = Model ModelData


type alias ModelData =
    { pendingTaskCount : PendingTaskCount
    , version : StoreVersion
    , project : Project
    , suppressedErrors : SuppressedErrors
    , ruleLinks : Dict String String
    , emptySourceDirectories : List String
    , directoriesFromCliArgsWithoutFiles : List String
    }


type alias PendingTaskCount =
    Int


init : FileSystem -> Options -> ( Model, Cmd Msg )
init fs options =
    let
        tasks : List (Cmd Msg)
        tasks =
            List.filterMap
                identity
                [ Just (fetchElmJson fs)
                , Just (fetchReadme fs)
                , if options.suppress then
                    Nothing

                  else
                    Just (fetchSuppressionFiles fs (SuppressedErrors.suppressedFolder options))
                , Just (fetchRuleLinks fs options)
                ]
    in
    ( Model
        { pendingTaskCount = List.length tasks
        , version = StoreVersion.zero
        , project = Project.new
        , suppressedErrors = SuppressedErrors.empty
        , ruleLinks = Dict.empty
        , emptySourceDirectories = []
        , directoriesFromCliArgsWithoutFiles = []
        }
    , Cmd.batch tasks
    )


type Readiness
    = Ready StoreVersion
    | Failure Problem
    | NotReady


checkReadiness : Model -> Readiness
checkReadiness (Model model) =
    if model.pendingTaskCount /= 0 then
        NotReady

    else if not (List.isEmpty model.directoriesFromCliArgsWithoutFiles) then
        { title = "NO FILES FOUND"
        , message =
            \_ -> """I was expecting to find Elm files in all the paths that you passed, but I could not find any in the following directories:
- """ ++ String.join "\n - " model.directoriesFromCliArgsWithoutFiles ++ """

When I can't find files in some of the directories, I'm assuming that you
misconfigured the CLI's arguments."""
        }
            |> Problem.from Problem.Recoverable
            |> Failure

    else if List.isEmpty (Project.modules model.project) then
        { title = "NO FILES FOUND"
        , message =
            \_ -> """I could not find any files in this project. I looked in these folders:
- """ ++ String.join "\n - " model.emptySourceDirectories
        }
            |> Problem.from Problem.Recoverable
            |> Failure

    else
        Ready model.version


type Msg
    = ReceivedElmJson Path (Result Fs.FsError String)
    | ReceivedReadme Path (Result Fs.FsError String)
    | ReceivedDependency String (Result Fs.FsError { elmJson : File, docsJson : File })
    | ReceivedElmFileList SourceDirectoryInfo (Result Fs.FsError (List Path))
    | ReceivedElmFile Path (Result Fs.FsError String)
    | ReceivedSuppressedErrorsList Path (Result Fs.FsError (List Path))
    | ReceivedSuppressedErrorsFile Path (Result Fs.FsError String)
    | ReceivedRuleLinks { links : Dict String String, fromCache : Bool }
    | GotProjectElmJsonWatchEvent
    | GotProjectReadmeWatchEvent FileEvent
    | GotSourceFileWatchEvent FileEvent
    | GotSuppressedFileWatchEvent FileEvent


type alias SourceDirectoryInfo =
    { fromCliArgs : Bool
    , target : Path
    }


type alias File =
    { path : Path
    , source : String
    }


type alias UpdateInput =
    { fs : FileSystem
    , stderr : Console
    , options : Options
    }


update : UpdateInput -> Msg -> Model -> ( Model, Cmd Msg )
update inputs msg (Model model) =
    updateInner inputs msg model
        |> Tuple.mapFirst Model


updateInner : UpdateInput -> Msg -> ModelData -> ( ModelData, Cmd Msg )
updateInner { fs, stderr, options } msg model =
    let
        decrementTaskCount : () -> ( ModelData, Cmd Msg )
        decrementTaskCount () =
            ( { pendingTaskCount = minimum (model.pendingTaskCount - 1)
              , version = model.version
              , project = model.project
              , suppressedErrors = model.suppressedErrors
              , ruleLinks = model.ruleLinks
              , emptySourceDirectories = model.emptySourceDirectories
              , directoriesFromCliArgsWithoutFiles = model.directoriesFromCliArgsWithoutFiles
              }
            , Cmd.none
            )

        handleProblem : Problem -> Cmd msg
        handleProblem problem =
            Problem.stop stderr
                { color = options.color
                , reportMode = options.reportMode
                , debug = options.debug
                , attemptFutureRecovery = options.watch
                }
                problem
    in
    case msg of
        ReceivedElmJson elmJsonPath (Ok rawElmJson) ->
            case Decode.decodeString Elm.Project.decoder rawElmJson of
                Ok elmJson ->
                    let
                        ( newTasksCount, tasks ) =
                            case fetchSources fs elmJsonPath elmJson options.directoriesToAnalyze of
                                Err problem ->
                                    ( 0
                                    , [ handleProblem problem ]
                                    )

                                Ok fetchSourceTasks ->
                                    let
                                        fetchTasks : List (Cmd Msg)
                                        fetchTasks =
                                            fetchDependencies fs options.packagesLocation elmJson fetchSourceTasks
                                    in
                                    ( List.length fetchTasks, fetchTasks )
                    in
                    ( { pendingTaskCount = minimum (model.pendingTaskCount + newTasksCount - 1)
                      , version = StoreVersion.increment model.version
                      , project = Project.addElmJson { path = elmJsonPath, raw = rawElmJson, project = elmJson } model.project
                      , suppressedErrors = model.suppressedErrors
                      , ruleLinks = model.ruleLinks
                      , emptySourceDirectories = model.emptySourceDirectories
                      , directoriesFromCliArgsWithoutFiles = model.directoriesFromCliArgsWithoutFiles
                      }
                    , Cmd.batch tasks
                    )

                Err _ ->
                    decrementTaskCount ()

        ReceivedElmJson path (Err err) ->
            ( { pendingTaskCount = minimum (model.pendingTaskCount - 1)
              , version = model.version
              , project = model.project
              , suppressedErrors = model.suppressedErrors
              , ruleLinks = model.ruleLinks
              , emptySourceDirectories = model.emptySourceDirectories
              , directoriesFromCliArgsWithoutFiles = model.directoriesFromCliArgsWithoutFiles
              }
            , { title = "PROBLEM READING ELM.JSON"
              , message = \c -> "I was trying to read " ++ c Yellow "elm.json" ++ " but encountered a problem:\n\n" ++ FsExtra.errorToString err
              }
                |> Problem.from Problem.Recoverable
                |> Problem.withPath path
                |> handleProblem
            )

        ReceivedReadme path result ->
            case result of
                Ok content ->
                    if Just content == Maybe.map .content (Project.readme model.project) then
                        decrementTaskCount ()

                    else
                        ( { pendingTaskCount = minimum (model.pendingTaskCount - 1)
                          , version = StoreVersion.increment model.version
                          , project = Project.addReadme { path = path, content = content } model.project
                          , suppressedErrors = model.suppressedErrors
                          , ruleLinks = model.ruleLinks
                          , emptySourceDirectories = model.emptySourceDirectories
                          , directoriesFromCliArgsWithoutFiles = model.directoriesFromCliArgsWithoutFiles
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
                            (Decode.decodeString Elm.Project.decoder elmJson.source |> Result.mapError (Tuple.pair elmJson.path))
                            (Decode.decodeString (Decode.list Elm.Docs.decoder) docsJson.source |> Result.mapError (Tuple.pair docsJson.path))
                    of
                        Ok dependency ->
                            if Just dependency == Dict.get packageName (Project.dependencies model.project) then
                                decrementTaskCount ()

                            else
                                ( { pendingTaskCount = minimum (model.pendingTaskCount - 1)
                                  , version = StoreVersion.increment model.version
                                  , project = Project.addDependency dependency model.project
                                  , suppressedErrors = model.suppressedErrors
                                  , ruleLinks = model.ruleLinks
                                  , emptySourceDirectories = model.emptySourceDirectories
                                  , directoriesFromCliArgsWithoutFiles = model.directoriesFromCliArgsWithoutFiles
                                  }
                                , Cmd.none
                                )

                        Err ( filePath, decodeError ) ->
                            if options.ignoreProblematicDependencies then
                                decrementTaskCount ()

                            else
                                ( { pendingTaskCount = minimum (model.pendingTaskCount - 1)
                                  , version = model.version
                                  , project = model.project
                                  , suppressedErrors = model.suppressedErrors
                                  , ruleLinks = model.ruleLinks
                                  , emptySourceDirectories = model.emptySourceDirectories
                                  , directoriesFromCliArgsWithoutFiles = model.directoriesFromCliArgsWithoutFiles
                                  }
                                , if String.contains "I need a valid module name like" (Decode.errorToString decodeError) then
                                    { title = "FOUND PROBLEMATIC DEPENDENCIES"
                                    , message =
                                        \_ ->
                                            """I encountered an error when reading the dependencies of the project. It seems due to dependencies with modules containing `_` in their names. Unfortunately, this is an error I have no control over and I am waiting in one of the libraries I depend on. What I propose you do, is to re-run elm-review like this:

    elm-review --ignore-problematic-dependencies

This will ignore the problematic dependencies, and can GIVE YOU INCORRECT RESULTS! This is a temporary measure.

If I am mistaken about the nature of the problem, please open a bug report at https://github.com/jfmengels/node-elm-review/issues:

"""
                                                ++ Decode.errorToString decodeError
                                    }
                                        |> Problem.from Problem.Recoverable
                                        |> Problem.withPath filePath
                                        |> handleProblem

                                  else
                                    { title = "PROBLEM READING DEPENDENCIES"
                                    , message =
                                        \_ ->
                                            "I encountered an error when reading the dependencies of the project. I suggest opening a bug report at https://github.com/jfmengels/node-elm-review/issues."
                                                ++ Decode.errorToString decodeError
                                    }
                                        |> Problem.from Problem.Recoverable
                                        |> Problem.withPath filePath
                                        |> handleProblem
                                )

                Err _ ->
                    -- TODO Download dependencies
                    decrementTaskCount ()

        ReceivedElmFileList { fromCliArgs, target } result ->
            receivedElmFileList
                { fs = fs
                , stderr = stderr
                , onNotFound =
                    \() ->
                        if fromCliArgs then
                            ( { pendingTaskCount = minimum (model.pendingTaskCount - 1)
                              , version = model.version
                              , project = model.project
                              , suppressedErrors = model.suppressedErrors
                              , ruleLinks = model.ruleLinks
                              , emptySourceDirectories = model.emptySourceDirectories
                              , directoriesFromCliArgsWithoutFiles = target :: model.directoriesFromCliArgsWithoutFiles
                              }
                            , Cmd.none
                            )

                        else
                            decrementTaskCount ()
                , handleProblem = handleProblem
                }
                target
                result
                model

        ReceivedElmFile path result ->
            case result of
                Ok source ->
                    -- TODO Use version of Project.modules that returns a Dict
                    if Just source == Maybe.map .source (find (\module_ -> module_.path == path) (Project.modules model.project)) then
                        decrementTaskCount ()

                    else
                        ( { pendingTaskCount = minimum (model.pendingTaskCount - 1)
                          , version = StoreVersion.increment model.version
                          , project = Project.addModule { path = path, source = source } model.project
                          , suppressedErrors = model.suppressedErrors
                          , ruleLinks = model.ruleLinks
                          , emptySourceDirectories = model.emptySourceDirectories
                          , directoriesFromCliArgsWithoutFiles = model.directoriesFromCliArgsWithoutFiles
                          }
                        , Cmd.none
                        )

                Err err ->
                    ( { pendingTaskCount = minimum (model.pendingTaskCount - 1)
                      , version = model.version
                      , project = model.project
                      , suppressedErrors = model.suppressedErrors
                      , ruleLinks = model.ruleLinks
                      , emptySourceDirectories = model.emptySourceDirectories
                      , directoriesFromCliArgsWithoutFiles = model.directoriesFromCliArgsWithoutFiles
                      }
                    , { title = "PROBLEM READING ELM FILE"
                      , message = \c -> "I was trying to read " ++ c Yellow path ++ " but encountered a problem:\n\n" ++ FsExtra.errorToString err
                      }
                        |> Problem.from Problem.Recoverable
                        |> Problem.withPath path
                        |> handleProblem
                    )

        ReceivedSuppressedErrorsList suppressedDirectory result ->
            case result of
                Ok files ->
                    ( { pendingTaskCount = minimum (model.pendingTaskCount + List.length files - 1)
                      , version = model.version
                      , project = model.project
                      , suppressedErrors = model.suppressedErrors
                      , ruleLinks = model.ruleLinks
                      , emptySourceDirectories = model.emptySourceDirectories
                      , directoriesFromCliArgsWithoutFiles = model.directoriesFromCliArgsWithoutFiles
                      }
                    , List.map
                        (\filePath ->
                            fetchSuppressionFile fs (Path.join2 suppressedDirectory filePath)
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
                    case SuppressedErrors.addFromFile path contents model.suppressedErrors of
                        Ok newSuppressedErrors ->
                            ( { pendingTaskCount = minimum (model.pendingTaskCount - 1)
                              , version = StoreVersion.increment model.version
                              , project = model.project
                              , suppressedErrors = newSuppressedErrors
                              , ruleLinks = model.ruleLinks
                              , emptySourceDirectories = model.emptySourceDirectories
                              , directoriesFromCliArgsWithoutFiles = model.directoriesFromCliArgsWithoutFiles
                              }
                            , Cmd.none
                            )

                        Err problem ->
                            ( { pendingTaskCount = minimum (model.pendingTaskCount - 1)
                              , version = model.version
                              , project = model.project
                              , suppressedErrors = model.suppressedErrors
                              , ruleLinks = model.ruleLinks
                              , emptySourceDirectories = model.emptySourceDirectories
                              , directoriesFromCliArgsWithoutFiles = model.directoriesFromCliArgsWithoutFiles
                              }
                            , handleProblem problem
                            )

                Err err ->
                    ( { pendingTaskCount = minimum (model.pendingTaskCount - 1)
                      , version = model.version
                      , project = model.project
                      , suppressedErrors = model.suppressedErrors
                      , ruleLinks = model.ruleLinks
                      , emptySourceDirectories = model.emptySourceDirectories
                      , directoriesFromCliArgsWithoutFiles = model.directoriesFromCliArgsWithoutFiles
                      }
                    , { title = "PROBLEM READING SUPPRESSION FILE"
                      , message = \c -> "I was trying to read " ++ c Orange path ++ " but encountered a problem:\n\n" ++ FsExtra.errorToString err
                      }
                        |> Problem.from Problem.Recoverable
                        |> Problem.withPath path
                        |> handleProblem
                    )

        ReceivedRuleLinks { links, fromCache } ->
            ( { pendingTaskCount = minimum (model.pendingTaskCount - 1)
              , version = StoreVersion.increment model.version
              , project = model.project
              , suppressedErrors = model.suppressedErrors
              , ruleLinks = links
              , emptySourceDirectories = model.emptySourceDirectories
              , directoriesFromCliArgsWithoutFiles = model.directoriesFromCliArgsWithoutFiles
              }
            , Cmd.none
            )

        GotProjectElmJsonWatchEvent ->
            ( { pendingTaskCount = model.pendingTaskCount + 1
              , version = model.version
              , project = model.project
              , suppressedErrors = model.suppressedErrors
              , ruleLinks = model.ruleLinks
              , emptySourceDirectories = model.emptySourceDirectories
              , directoriesFromCliArgsWithoutFiles = model.directoriesFromCliArgsWithoutFiles
              }
            , fetchElmJson fs
            )

        GotProjectReadmeWatchEvent fileEvent ->
            let
                ( newProject, version, cmd ) =
                    if fileEvent.eventType == 4 {- file was deleted -} then
                        -- TODO Remove README.md from project
                        ( model.project, StoreVersion.increment model.version, [] )

                    else
                        {- file was added or modified -}
                        ( model.project, model.version, [ fetchReadme fs ] )
            in
            ( { pendingTaskCount = model.pendingTaskCount + List.length cmd
              , version = version
              , project = newProject
              , suppressedErrors = model.suppressedErrors
              , ruleLinks = model.ruleLinks
              , emptySourceDirectories = model.emptySourceDirectories
              , directoriesFromCliArgsWithoutFiles = model.directoriesFromCliArgsWithoutFiles
              }
            , Cmd.batch cmd
            )

        GotSourceFileWatchEvent fileEvent ->
            if String.endsWith ".elm" fileEvent.path then
                let
                    ( newProject, version, cmds ) =
                        case FileWatcher.toEventType fileEvent.eventType of
                            FileWatcher.Created ->
                                ( model.project, model.version, [ fetchElmFile fs fileEvent.path ] )

                            FileWatcher.Modified ->
                                ( model.project, model.version, [ fetchElmFile fs fileEvent.path ] )

                            FileWatcher.Deleted ->
                                ( Project.removeFile fileEvent.path model.project
                                , StoreVersion.increment model.version
                                , []
                                )

                            FileWatcher.Renamed ->
                                ( Project.removeFile fileEvent.path model.project
                                , StoreVersion.increment model.version
                                , [ fetchElmFile fs fileEvent.path ]
                                )
                in
                ( { pendingTaskCount = model.pendingTaskCount + List.length cmds
                  , version = version
                  , project = newProject
                  , suppressedErrors = model.suppressedErrors
                  , ruleLinks = model.ruleLinks
                  , emptySourceDirectories = model.emptySourceDirectories
                  , directoriesFromCliArgsWithoutFiles = model.directoriesFromCliArgsWithoutFiles
                  }
                , Cmd.batch cmds
                )

            else
                ( model, Cmd.none )

        GotSuppressedFileWatchEvent fileEvent ->
            if isSuppressedErrorFile fileEvent.path then
                let
                    ( newSuppressedErrors, version, cmds ) =
                        if fileEvent.eventType == 4 {- file was deleted -} then
                            ( SuppressedErrors.removeFromFile fileEvent.path model.suppressedErrors
                            , StoreVersion.increment model.version
                            , []
                            )

                        else
                            {- file was added or modified -}
                            ( model.suppressedErrors
                            , model.version
                            , [ fetchSuppressionFile fs fileEvent.path ]
                            )
                in
                ( { pendingTaskCount = model.pendingTaskCount + List.length cmds
                  , version = version
                  , project = model.project
                  , suppressedErrors = newSuppressedErrors
                  , ruleLinks = model.ruleLinks
                  , emptySourceDirectories = model.emptySourceDirectories
                  , directoriesFromCliArgsWithoutFiles = model.directoriesFromCliArgsWithoutFiles
                  }
                , Cmd.batch cmds
                )

            else
                ( model, Cmd.none )


isSuppressedErrorFile : Path -> Bool
isSuppressedErrorFile path =
    String.endsWith ".json" path


fetchSources : FileSystem -> Path -> Elm.Project.Project -> Maybe (List Path) -> Result Problem (List (Cmd Msg))
fetchSources fs elmJsonPath elmJson directoriesToAnalyze =
    case filesToFetch elmJson directoriesToAnalyze of
        Ok targets ->
            List.map
                (\sourceDirectoryInfo ->
                    fetchElmFiles fs sourceDirectoryInfo
                        |> Task.attempt (ReceivedElmFileList sourceDirectoryInfo)
                )
                targets
                |> Ok

        Err problem ->
            problem
                |> Problem.from Problem.Recoverable
                |> Problem.withPath elmJsonPath
                |> Err


filesToFetch : Elm.Project.Project -> Maybe (List Path) -> Result ProblemSimple (List SourceDirectoryInfo)
filesToFetch elmJson directoriesToAnalyze =
    case directoriesToAnalyze of
        Nothing ->
            case elmJson of
                Elm.Project.Application application ->
                    if List.isEmpty application.dirs then
                        { title = "EMPTY SOURCE-DIRECTORIES"
                        , message = \_ -> """The `source-directories` in your `elm.json` is empty. I need it to contain at least 1 directory in order to find files to analyze. The Elm compiler will need that as well anyway."""
                        }
                            |> Err

                    else
                        List.map (\directory -> { fromCliArgs = False, target = directory }) ("test" :: application.dirs)
                            |> Ok

                Elm.Project.Package _ ->
                    List.map (\directory -> { fromCliArgs = False, target = directory }) [ "src", "test" ]
                        |> Ok

        Just directoriesToAnalyze_ ->
            List.map
                (\fileOrDir ->
                    { fromCliArgs = True, target = fileOrDir }
                )
                directoriesToAnalyze_
                |> Ok


fetchDependencies : FileSystem -> Path -> Elm.Project.Project -> List (Cmd Msg) -> List (Cmd Msg)
fetchDependencies fs packagesLocation elmJson initial =
    case elmJson of
        Elm.Project.Application application ->
            initial
                |> addDepsFromVersion fs packagesLocation application.depsDirect
                |> addDepsFromVersion fs packagesLocation application.depsIndirect
                |> addDepsFromVersion fs packagesLocation application.testDepsDirect
                |> addDepsFromVersion fs packagesLocation application.testDepsIndirect

        Elm.Project.Package package ->
            initial
                |> addDepsFromConstraint fs packagesLocation package.deps
                |> addDepsFromConstraint fs packagesLocation package.testDeps


addDepsFromVersion : FileSystem -> Path -> List ( Elm.Package.Name, Elm.Version.Version ) -> List (Cmd Msg) -> List (Cmd Msg)
addDepsFromVersion fs packagesLocation deps initial =
    List.foldl
        (\( name, version ) acc ->
            fetchDependency fs packagesLocation (Elm.Package.toString name) (Elm.Version.toString version) :: acc
        )
        initial
        deps


addDepsFromConstraint : FileSystem -> Path -> List ( Elm.Package.Name, Elm.Constraint.Constraint ) -> List (Cmd Msg) -> List (Cmd Msg)
addDepsFromConstraint fs packagesLocation deps initial =
    List.foldl
        (\( name, constraint ) acc ->
            case Elm.Constraint.toString constraint |> String.split " " |> List.head of
                Just minVersion ->
                    fetchDependency fs packagesLocation (Elm.Package.toString name) minVersion :: acc

                Nothing ->
                    acc
        )
        initial
        deps


receivedElmFileList :
    { fs : FileSystem
    , stderr : Console
    , onNotFound : () -> ( ModelData, Cmd Msg )
    , handleProblem : Problem -> Cmd Msg
    }
    -> Path
    -> Result FsError (List Path)
    -> ModelData
    -> ( ModelData, Cmd Msg )
receivedElmFileList { fs, stderr, onNotFound, handleProblem } directory result model =
    case result of
        Ok files ->
            let
                ( emptySourceDirectories, version ) =
                    if List.isEmpty files then
                        ( directory :: model.emptySourceDirectories, StoreVersion.increment model.version )

                    else
                        ( model.emptySourceDirectories, model.version )
            in
            ( { pendingTaskCount = minimum (model.pendingTaskCount + List.length files - 1)
              , version = version
              , project = model.project
              , suppressedErrors = model.suppressedErrors
              , ruleLinks = model.ruleLinks
              , emptySourceDirectories = emptySourceDirectories
              , directoriesFromCliArgsWithoutFiles = model.directoriesFromCliArgsWithoutFiles
              }
            , List.map (\filePath -> fetchElmFile fs filePath) files
                |> Cmd.batch
            )

        Err (Fs.NotFound _) ->
            onNotFound ()

        Err err ->
            ( { pendingTaskCount = minimum (model.pendingTaskCount - 1)
              , version = model.version
              , project = model.project
              , suppressedErrors = model.suppressedErrors
              , ruleLinks = model.ruleLinks
              , emptySourceDirectories = model.emptySourceDirectories
              , directoriesFromCliArgsWithoutFiles = model.directoriesFromCliArgsWithoutFiles
              }
            , { title = "PROBLEM FINDING ELM FILES"
              , message = \_ -> "I was trying to find the Elm files in your project but encountered a problem:\n\n" ++ FsExtra.errorToString err
              }
                |> Problem.from Problem.Recoverable
                |> Problem.withPath directory
                |> handleProblem
            )


applyChangesFromFix : FileSystem -> Options -> Project -> Model -> ( Model, Cmd Msg )
applyChangesFromFix fs options projectWithFixes model =
    case
        changesInElmJson
            options.directoriesToAnalyze
            { before = Project.elmJson (project model)
            , after = Project.elmJson projectWithFixes
            }
    of
        NoChanges ->
            ( setProject projectWithFixes model
            , Cmd.none
            )

        ReloadDependencies newElmJson ->
            refreshProjectDependencies fs options.packagesLocation newElmJson projectWithFixes model

        ReloadCompletely ->
            init fs options


type ElmJsonChanges
    = NoChanges
    | ReloadDependencies Elm.Project.Project
    | ReloadCompletely


changesInElmJson :
    Maybe (List Path)
    ->
        { before : Maybe { a | project : Elm.Project.Project }
        , after : Maybe { a | project : Elm.Project.Project }
        }
    -> ElmJsonChanges
changesInElmJson directoriesToAnalyze { before, after } =
    case ( Maybe.map .project before, Maybe.map .project after ) of
        ( Nothing, Nothing ) ->
            NoChanges

        ( Just (Elm.Project.Application a), Just ((Elm.Project.Application b) as newProject) ) ->
            if a.dirs /= b.dirs && not (List.isEmpty (Maybe.withDefault [] directoriesToAnalyze)) then
                ReloadCompletely

            else if a.elm /= b.elm || a /= b then
                ReloadDependencies newProject

            else
                NoChanges

        ( Just (Elm.Project.Package a), Just ((Elm.Project.Package b) as newProject) ) ->
            if a.elm /= b.elm || a.deps /= b.deps || a.testDeps /= b.testDeps then
                ReloadDependencies newProject

            else
                NoChanges

        _ ->
            ReloadCompletely


refreshProjectDependencies : FileSystem -> Path -> Elm.Project.Project -> Project -> Model -> ( Model, Cmd Msg )
refreshProjectDependencies fs packagesLocation elmJson newProject (Model model) =
    let
        tasks : List (Cmd Msg)
        tasks =
            fetchDependencies fs packagesLocation elmJson []
    in
    ( Model
        { pendingTaskCount = model.pendingTaskCount + List.length tasks
        , version = StoreVersion.increment model.version
        , project = Project.removeDependencies newProject
        , suppressedErrors = model.suppressedErrors
        , ruleLinks = model.ruleLinks
        , emptySourceDirectories = model.emptySourceDirectories
        , directoriesFromCliArgsWithoutFiles = model.directoriesFromCliArgsWithoutFiles
        }
    , Cmd.batch tasks
    )


setProject : Project -> Model -> Model
setProject newProject (Model model) =
    Model
        { pendingTaskCount = model.pendingTaskCount
        , version = StoreVersion.increment model.version
        , project = newProject
        , suppressedErrors = model.suppressedErrors
        , ruleLinks = model.ruleLinks
        , emptySourceDirectories = model.emptySourceDirectories
        , directoriesFromCliArgsWithoutFiles = model.directoriesFromCliArgsWithoutFiles
        }


minimum : Int -> Int
minimum =
    Basics.max 0


project : Model -> Project
project (Model model) =
    model.project


suppressedErrors : Model -> SuppressedErrors
suppressedErrors (Model model) =
    model.suppressedErrors


setSuppressedErrors : SuppressedErrors -> Model -> Model
setSuppressedErrors newSuppressedErrors (Model model) =
    Model
        { pendingTaskCount = model.pendingTaskCount
        , version = StoreVersion.increment model.version
        , project = model.project
        , suppressedErrors = newSuppressedErrors
        , ruleLinks = model.ruleLinks
        , emptySourceDirectories = model.emptySourceDirectories
        , directoriesFromCliArgsWithoutFiles = model.directoriesFromCliArgsWithoutFiles
        }


ruleLinks : Model -> Dict String String
ruleLinks (Model model) =
    model.ruleLinks


fetchElmFile : FileSystem -> Path -> Cmd Msg
fetchElmFile fs filePath =
    Fs.readTextFile fs filePath
        |> Task.attempt (ReceivedElmFile filePath)


fetchSuppressionFile : FileSystem -> Path -> Cmd Msg
fetchSuppressionFile fs filePath =
    Fs.readTextFile fs filePath
        |> Task.attempt (ReceivedSuppressedErrorsFile filePath)


fetchElmJson : FileSystem -> Cmd Msg
fetchElmJson fs =
    readTextFile fs ReceivedElmJson "elm.json"


fetchReadme : FileSystem -> Cmd Msg
fetchReadme fs =
    readTextFile fs ReceivedReadme "README.md"


fetchSuppressionFiles : FileSystem -> Path -> Cmd Msg
fetchSuppressionFiles fs suppressedDirectory =
    Fs.walkTree fs suppressedDirectory (Just "*.json") Fs.Any
        |> Task.map
            (\( files, _ ) ->
                -- Remove leading "./"
                List.map (String.dropLeft 2) files
            )
        |> Task.attempt (ReceivedSuppressedErrorsList suppressedDirectory)


fetchElmFiles : FileSystem -> SourceDirectoryInfo -> Task FsError (List String)
fetchElmFiles fs sourceDirectoryInfo =
    if sourceDirectoryInfo.fromCliArgs && String.endsWith ".elm" sourceDirectoryInfo.target then
        Task.succeed [ sourceDirectoryInfo.target ]

    else
        Fs.walkTree fs sourceDirectoryInfo.target (Just "*.elm") Fs.Any
            |> Task.map (\( files, _ ) -> List.map (Path.join2 sourceDirectoryInfo.target) files)


fetchDependency : FileSystem -> Path -> String -> String -> Cmd Msg
fetchDependency fs packagesLocation packageName packageVersion =
    let
        directory : String
        directory =
            Path.join [ packagesLocation, packageName, packageVersion ]
    in
    Task.map2 (\elmJson docsJson -> { elmJson = elmJson, docsJson = docsJson })
        (readTextFileWithPath fs (Path.join2 directory "elm.json"))
        (readTextFileWithPath fs (Path.join2 directory "docs.json"))
        |> Task.attempt (ReceivedDependency packageName)


fetchRuleLinks : FileSystem -> { options | reviewFolder : Path, packagesLocation : Path } -> Cmd Msg
fetchRuleLinks fs { reviewFolder, packagesLocation } =
    Fs.readTextFile fs (Path.join2 reviewFolder "elm.json")
        |> Task.andThen
            (\elmJson ->
                case Decode.decodeString Elm.Project.decoder elmJson of
                    Ok (Elm.Project.Application { depsDirect, depsIndirect }) ->
                        FsExtra.mapAllAndFold
                            (readElmJson fs packagesLocation)
                            (\deps dict -> List.foldl (\( name, dep ) d -> Dict.insert name dep d) dict deps)
                            Dict.empty
                            (depsDirect ++ depsIndirect)

                    _ ->
                        Task.succeed Dict.empty
            )
        |> Task.onError (\_ -> Task.succeed Dict.empty)
        |> Task.perform (\links -> ReceivedRuleLinks { links = links, fromCache = False })


readElmJson : FileSystem -> Path -> ( Elm.Package.Name, Elm.Version.Version ) -> Task x (List ( String, String ))
readElmJson fs packagesLocation ( rawPackageName, rawPackageVersion ) =
    let
        packageName : String
        packageName =
            Elm.Package.toString rawPackageName

        packageVersion : String
        packageVersion =
            Elm.Version.toString rawPackageVersion
    in
    Path.join [ packagesLocation, packageName, packageVersion, "elm.json" ]
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


readTextFileWithPath : FileSystem -> String -> Task FsError File
readTextFileWithPath fs path =
    Fs.readTextFile fs path
        |> Task.map (\source -> { path = path, source = source })


subscriptions : FileWatcher -> Options -> Model -> Sub Msg
subscriptions fileWatcher options (Model model) =
    Sub.batch
        [ watchPath fileWatcher
            { path = "elm.json"
            , toMsg = \_ -> GotProjectElmJsonWatchEvent
            , recursive = False
            , eventMask = 3
            }
        , watchPath fileWatcher
            { path = "README.md"
            , toMsg = GotProjectReadmeWatchEvent
            , recursive = False
            , eventMask = 7
            }
        , watchSourceDirectories fileWatcher options model
        , watchSuppressedFiles fileWatcher options
        ]


watchSourceDirectories : FileWatcher -> Options -> ModelData -> Sub Msg
watchSourceDirectories fileWatcher options model =
    case Project.elmJson model.project of
        Just elmJson ->
            case filesToFetch elmJson.project options.directoriesToAnalyze of
                Ok targets ->
                    targets
                        |> List.map
                            (\{ fromCliArgs, target } ->
                                watchPath fileWatcher
                                    { path = target
                                    , toMsg = GotSourceFileWatchEvent
                                    , recursive = not (fromCliArgs && String.endsWith ".elm" target)
                                    , eventMask = 15
                                    }
                            )
                        |> Sub.batch

                Err _ ->
                    Sub.none

        Nothing ->
            Sub.none


watchSuppressedFiles : FileWatcher -> Options -> Sub Msg
watchSuppressedFiles fileWatcher options =
    watchPath fileWatcher
        { path = SuppressedErrors.suppressedFolder options
        , toMsg = GotSuppressedFileWatchEvent
        , recursive = False -- TODO Should this be True?
        , eventMask = 7
        }


watchPath : FileWatcher -> { toMsg : FileEvent -> Msg, path : Path, recursive : Bool, eventMask : Int } -> Sub Msg
watchPath fileWatcher { toMsg, path, recursive, eventMask } =
    FileWatcher.watch
        fileWatcher
        path
        -- If the path explicitly mentions an excluded path (e.g. "./node_modules/elm-library/src")
        -- then re-include that path.
        { excludePaths = List.filter (\excludePath -> not (String.contains excludePath path)) excludePaths
        , recursive = recursive
        , coalesceMs = 100
        , eventMask = eventMask
        }
        toMsg


excludePaths : List String
excludePaths =
    [ ".git", "node_modules", "elm-stuff" ]


{-| Find the first element that satisfies a predicate and return
Just that element. If none match, return Nothing.
find (\\num -> num > 5) [2, 4, 6, 8] == Just 6
-}
find : (a -> Bool) -> List a -> Maybe a
find predicate list =
    case list of
        [] ->
            Nothing

        first :: rest ->
            if predicate first then
                Just first

            else
                find predicate rest

module Elm.Review.Store exposing
    ( Model, init
    , Msg, update
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
import Elm.Review.Testable.Cmd as TCmd
import Elm.Review.Testable.FileWatchData as FileWatchData exposing (FileEvent)
import Elm.Review.Testable.FileWatcher as FileWatcher
import Elm.Review.Testable.Fs as Fs
import Elm.Review.Testable.FsData as FsData exposing (FsError)
import Elm.Review.Testable.Http as Http
import Elm.Review.Testable.Internal exposing (TCmd)
import Elm.Review.Testable.TSub as TSub exposing (TSub)
import Elm.Review.Testable.TTask as TTask exposing (TTask)
import Elm.Version
import ElmReview.Color exposing (Color(..))
import ElmReview.Path as Path exposing (Path)
import ElmReview.Problem as Problem exposing (Problem)
import Json.Decode as Decode
import Review.Project as Project exposing (Project)
import Review.Project.Dependency as Dependency


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


init : Options -> ( Model, TCmd Msg )
init options =
    let
        tasks : List (TCmd Msg)
        tasks =
            List.filterMap
                identity
                [ Just fetchElmJson
                , Just fetchReadme
                , if options.suppress then
                    Nothing

                  else
                    Just (fetchSuppressionFiles (SuppressedErrors.suppressedFolder options))
                , Just (fetchRuleLinks options)
                ]

        tasksWithFileFetch : List (TCmd Msg)
        tasksWithFileFetch =
            case options.directoriesToAnalyze of
                Just directoriesToAnalyze ->
                    List.foldl
                        (\fileOrDir acc ->
                            TTask.attempt (ReceivedElmFileList fileOrDir)
                                (if String.endsWith ".elm" fileOrDir then
                                    TTask.succeed [ fileOrDir ]

                                 else
                                    Fs.walkTree fileOrDir (Just "*.elm") FsData.Any
                                        |> TTask.map (\files -> List.map (Path.join2 fileOrDir) files)
                                )
                                :: acc
                        )
                        tasks
                        directoriesToAnalyze

                Nothing ->
                    tasks
    in
    ( Model
        { pendingTaskCount = List.length tasksWithFileFetch
        , version = StoreVersion.zero
        , project = Project.new
        , suppressedErrors = SuppressedErrors.empty
        , ruleLinks = Dict.empty
        , emptySourceDirectories = []
        , directoriesFromCliArgsWithoutFiles = []
        }
    , TCmd.batch tasksWithFileFetch
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
        -- TODO Use version of Project.modules so that the check is fast
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
    = ReceivedElmJson (Result FsData.FsError String)
    | ReceivedReadme (Result FsData.FsError String)
    | ReceivedDependency String (Result FsData.FsError { elmJson : File, docsJson : File })
    | ReceivedElmFileList Path (Result FsData.FsError (List Path))
    | ReceivedElmFile Path (Result FsData.FsError String)
    | ReceivedSuppressedErrorsList Path (Result FsData.FsError (List Path))
    | ReceivedSuppressedErrorsFile Path (Result FsData.FsError String)
    | ReceivedRuleLinks { links : Dict String String, fromCache : Bool }
    | GotProjectElmJsonWatchEvent
    | GotProjectReadmeWatchEvent FileEvent
    | GotSourceFileWatchEvent FileEvent
    | GotSuppressedFileWatchEvent FileEvent


type alias File =
    { path : Path
    , source : String
    }


update : Options -> Msg -> Model -> ( Model, TCmd Msg )
update options msg (Model model) =
    updateInner options msg model
        |> Tuple.mapFirst Model


updateInner : Options -> Msg -> ModelData -> ( ModelData, TCmd Msg )
updateInner options msg model =
    let
        decrementTaskCount : () -> ( ModelData, TCmd Msg )
        decrementTaskCount () =
            ( { pendingTaskCount = minimum (model.pendingTaskCount - 1)
              , version = model.version
              , project = model.project
              , suppressedErrors = model.suppressedErrors
              , ruleLinks = model.ruleLinks
              , emptySourceDirectories = model.emptySourceDirectories
              , directoriesFromCliArgsWithoutFiles = model.directoriesFromCliArgsWithoutFiles
              }
            , TCmd.none
            )

        handleProblem : Problem -> TCmd msg
        handleProblem problem =
            Problem.stop
                { color = options.color
                , reportMode = options.reportMode
                , debug = options.debug
                , attemptFutureRecovery = options.watch
                }
                problem
    in
    case msg of
        ReceivedElmJson (Ok rawElmJson) ->
            case Decode.decodeString Elm.Project.decoder rawElmJson of
                Ok elmJson ->
                    let
                        previousElmJson : Maybe { path : String, raw : String, project : Elm.Project.Project }
                        previousElmJson =
                            Project.elmJson model.project

                        elmJsonData : { path : Path, raw : String, project : Elm.Project.Project }
                        elmJsonData =
                            { path = elmJsonPath, raw = rawElmJson, project = elmJson }

                        newProject : Project
                        newProject =
                            Project.addElmJson elmJsonData model.project
                    in
                    fetchDataOnElmJsonChange
                        options
                        previousElmJson
                        elmJsonData
                        { model
                            | pendingTaskCount = minimum (model.pendingTaskCount - 1)
                            , project = newProject
                        }

                Err _ ->
                    decrementTaskCount ()

        ReceivedElmJson (Err err) ->
            ( { pendingTaskCount = minimum (model.pendingTaskCount - 1)
              , version = model.version
              , project = model.project
              , suppressedErrors = model.suppressedErrors
              , ruleLinks = model.ruleLinks
              , emptySourceDirectories = model.emptySourceDirectories
              , directoriesFromCliArgsWithoutFiles = model.directoriesFromCliArgsWithoutFiles
              }
            , { title = "PROBLEM READING ELM.JSON"
              , message = \c -> "I was trying to read " ++ c Yellow elmJsonPath ++ " but encountered a problem:\n\n" ++ FsData.errorToString err
              }
                |> Problem.from Problem.Recoverable
                |> Problem.withPath elmJsonPath
                |> handleProblem
            )

        ReceivedReadme result ->
            case result of
                Ok content ->
                    if Just content == Maybe.map .content (Project.readme model.project) then
                        decrementTaskCount ()

                    else
                        ( { pendingTaskCount = minimum (model.pendingTaskCount - 1)
                          , version = StoreVersion.increment model.version
                          , project = Project.addReadme { path = readmePath, content = content } model.project
                          , suppressedErrors = model.suppressedErrors
                          , ruleLinks = model.ruleLinks
                          , emptySourceDirectories = model.emptySourceDirectories
                          , directoriesFromCliArgsWithoutFiles = model.directoriesFromCliArgsWithoutFiles
                          }
                        , TCmd.none
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
                                , TCmd.none
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

        ReceivedElmFileList path result ->
            receivedElmFileList
                { onNotFound =
                    \() ->
                        case options.directoriesToAnalyze of
                            Just _ ->
                                ( { pendingTaskCount = minimum (model.pendingTaskCount - 1)
                                  , version = model.version
                                  , project = model.project
                                  , suppressedErrors = model.suppressedErrors
                                  , ruleLinks = model.ruleLinks
                                  , emptySourceDirectories = model.emptySourceDirectories
                                  , directoriesFromCliArgsWithoutFiles = path :: model.directoriesFromCliArgsWithoutFiles
                                  }
                                , TCmd.none
                                )

                            Nothing ->
                                decrementTaskCount ()
                , handleProblem = handleProblem
                }
                path
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
                        , TCmd.none
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
                      , message = \c -> "I was trying to read " ++ c Yellow path ++ " but encountered a problem:\n\n" ++ FsData.errorToString err
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
                            fetchSuppressionFile (Path.join2 suppressedDirectory filePath)
                        )
                        files
                        |> TCmd.batch
                    )

                Err (FsData.NotFound _) ->
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
                            , TCmd.none
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
                      , message = \c -> "I was trying to read " ++ c Orange path ++ " but encountered a problem:\n\n" ++ FsData.errorToString err
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
            , TCmd.none
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
            , fetchElmJson
            )

        GotProjectReadmeWatchEvent fileEvent ->
            let
                ( newProject, version, cmd ) =
                    if fileEvent.eventType == 4 {- file was deleted -} then
                        -- TODO Remove README.md from project
                        ( model.project, StoreVersion.increment model.version, [] )

                    else
                        {- file was added or modified -}
                        ( model.project, model.version, [ fetchReadme ] )
            in
            ( { pendingTaskCount = model.pendingTaskCount + List.length cmd
              , version = version
              , project = newProject
              , suppressedErrors = model.suppressedErrors
              , ruleLinks = model.ruleLinks
              , emptySourceDirectories = model.emptySourceDirectories
              , directoriesFromCliArgsWithoutFiles = model.directoriesFromCliArgsWithoutFiles
              }
            , TCmd.batch cmd
            )

        GotSourceFileWatchEvent fileEvent ->
            if String.endsWith ".elm" fileEvent.path then
                let
                    ( newProject, version, cmds ) =
                        case FileWatchData.toEventType fileEvent.eventType of
                            FileWatchData.Created ->
                                ( model.project, model.version, [ fetchElmFile fileEvent.path ] )

                            FileWatchData.Modified ->
                                ( model.project, model.version, [ fetchElmFile fileEvent.path ] )

                            FileWatchData.Deleted ->
                                ( Project.removeFile fileEvent.path model.project
                                , StoreVersion.increment model.version
                                , []
                                )

                            FileWatchData.Renamed ->
                                ( Project.removeFile fileEvent.path model.project
                                , StoreVersion.increment model.version
                                , [ fetchElmFile fileEvent.path ]
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
                , TCmd.batch cmds
                )

            else
                ( model, TCmd.none )

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
                            , [ fetchSuppressionFile fileEvent.path ]
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
                , TCmd.batch cmds
                )

            else
                ( model, TCmd.none )


isSuppressedErrorFile : Path -> Bool
isSuppressedErrorFile path =
    String.endsWith ".json" path


elmFilesToFetch : Elm.Project.Project -> Maybe (List Path) -> Result Problem (List Path)
elmFilesToFetch elmJson directoriesToAnalyze =
    case directoriesToAnalyze of
        Nothing ->
            case elmJson of
                Elm.Project.Application application ->
                    if List.isEmpty application.dirs then
                        { title = "EMPTY SOURCE-DIRECTORIES"
                        , message = \_ -> """The `source-directories` in your `elm.json` is empty. I need it to contain at least 1 directory in order to find files to analyze. The Elm compiler will need that as well anyway."""
                        }
                            |> Problem.from Problem.Recoverable
                            |> Problem.withPath elmJsonPath
                            |> Err

                    else
                        Ok ("test" :: application.dirs)

                Elm.Project.Package _ ->
                    Ok [ "src", "test" ]

        Just directoriesToAnalyze_ ->
            Ok directoriesToAnalyze_


addDepsFromVersion : Options -> List ( Elm.Package.Name, Elm.Version.Version ) -> List (TCmd Msg) -> List (TCmd Msg)
addDepsFromVersion options deps initial =
    List.foldl
        (\( name, version ) acc ->
            fetchDependency options (Elm.Package.toString name) (Elm.Version.toString version) :: acc
        )
        initial
        deps


addDepsFromConstraint : Options -> List ( Elm.Package.Name, Elm.Constraint.Constraint ) -> List (TCmd Msg) -> List (TCmd Msg)
addDepsFromConstraint options deps initial =
    List.foldl
        (\( name, constraint ) acc ->
            case Elm.Constraint.toString constraint |> String.split " " |> List.head of
                Just minVersion ->
                    fetchDependency options (Elm.Package.toString name) minVersion :: acc

                Nothing ->
                    acc
        )
        initial
        deps


receivedElmFileList :
    { onNotFound : () -> ( ModelData, TCmd Msg )
    , handleProblem : Problem -> TCmd Msg
    }
    -> Path
    -> Result FsError (List Path)
    -> ModelData
    -> ( ModelData, TCmd Msg )
receivedElmFileList { onNotFound, handleProblem } directory result model =
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
            , List.map (\filePath -> fetchElmFile filePath) files
                |> TCmd.batch
            )

        Err (FsData.NotFound _) ->
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
              , message = \_ -> "I was trying to find the Elm files in your project but encountered a problem:\n\n" ++ FsData.errorToString err
              }
                |> Problem.from Problem.Recoverable
                |> Problem.withPath directory
                |> handleProblem
            )


applyChangesFromFix : Options -> Project -> Model -> ( Model, TCmd Msg )
applyChangesFromFix options projectWithFixes (Model model) =
    let
        newModel : ModelData
        newModel =
            { model
                | version = StoreVersion.increment model.version
                , project = projectWithFixes
            }
    in
    case Project.elmJson projectWithFixes of
        Just elmJson ->
            fetchDataOnElmJsonChange
                options
                (Project.elmJson model.project)
                elmJson
                newModel
                |> Tuple.mapFirst Model

        Nothing ->
            ( Model newModel, TCmd.none )


fetchDataOnElmJsonChange :
    Options
    -> Maybe { elmJson | raw : String, project : Elm.Project.Project }
    -> { elmJson | raw : String, project : Elm.Project.Project }
    -> ModelData
    -> ( ModelData, TCmd Msg )
fetchDataOnElmJsonChange options before after model =
    if Maybe.map .raw before == Just after.raw then
        ( model, TCmd.none )

    else
        case changesInElmJson options.directoriesToAnalyze { before = Maybe.map .project before, after = after.project } of
            Ok { sourceDirectories, dependencies } ->
                let
                    tasks : List (TCmd Msg)
                    tasks =
                        fetchAddedSourceDirectories sourceDirectories.added
                            |> fetchAddedDependencies options dependencies

                    newProject : Project
                    newProject =
                        model.project
                            |> removeSourceDirectories sourceDirectories.removed
                            |> removeDependencies dependencies
                in
                ( { pendingTaskCount = model.pendingTaskCount + List.length tasks
                  , version = StoreVersion.increment model.version
                  , project = newProject
                  , suppressedErrors = model.suppressedErrors
                  , ruleLinks = model.ruleLinks
                  , emptySourceDirectories = model.emptySourceDirectories
                  , directoriesFromCliArgsWithoutFiles = model.directoriesFromCliArgsWithoutFiles
                  }
                , TCmd.batch tasks
                )

            Err problem ->
                ( model
                , Problem.stop
                    { color = options.color
                    , reportMode = options.reportMode
                    , debug = options.debug
                    , attemptFutureRecovery = options.watch
                    }
                    problem
                )


type alias ElmJsonChanges =
    { sourceDirectories : { added : List Path, removed : List Path }
    , dependencies : ElmJsonDependencyChanges
    }


type ElmJsonDependencyChanges
    = NoDependencyChanges
    | DiffApplication { added : List ( Elm.Package.Name, Elm.Version.Version ), removed : List Elm.Package.Name }
    | DiffPackages { added : List ( Elm.Package.Name, Elm.Constraint.Constraint ), removed : List Elm.Package.Name }
    | ReloadDependenciesEntirely Elm.Project.Project


changesInElmJson :
    Maybe (List Path)
    ->
        { before : Maybe Elm.Project.Project
        , after : Elm.Project.Project
        }
    -> Result Problem ElmJsonChanges
changesInElmJson directoriesToAnalyze beforeAndAfter =
    sourceDirectoryChangesInElmJson directoriesToAnalyze beforeAndAfter
        |> Result.map
            (\sourceDirectories ->
                { sourceDirectories = sourceDirectories
                , dependencies = dependencyChangesInElmJson beforeAndAfter
                }
            )


sourceDirectoryChangesInElmJson :
    Maybe (List Path)
    ->
        { before : Maybe Elm.Project.Project
        , after : Elm.Project.Project
        }
    -> Result Problem { added : List String, removed : List Path }
sourceDirectoryChangesInElmJson directoriesToAnalyze { before, after } =
    Result.map2 diffSourceDirectories
        (case before of
            Just before_ ->
                elmFilesToFetch before_ directoriesToAnalyze

            Nothing ->
                Ok []
        )
        (elmFilesToFetch after directoriesToAnalyze)


dependencyChangesInElmJson :
    { before : Maybe Elm.Project.Project
    , after : Elm.Project.Project
    }
    -> ElmJsonDependencyChanges
dependencyChangesInElmJson { before, after } =
    case ( before, after ) of
        ( Nothing, (Elm.Project.Application _) as newProject ) ->
            ReloadDependenciesEntirely newProject

        ( Nothing, (Elm.Project.Package _) as newProject ) ->
            ReloadDependenciesEntirely newProject

        ( Just (Elm.Project.Application a), Elm.Project.Application b ) ->
            case diffDependencies (a.depsDirect ++ a.depsIndirect ++ a.testDepsDirect ++ a.testDepsIndirect) (b.depsDirect ++ b.depsIndirect ++ b.testDepsDirect ++ b.testDepsIndirect) of
                Nothing ->
                    NoDependencyChanges

                Just changes ->
                    DiffApplication changes

        ( Just (Elm.Project.Package a), Elm.Project.Package b ) ->
            case diffDependencies (a.deps ++ a.testDeps) (b.deps ++ b.testDeps) of
                Nothing ->
                    NoDependencyChanges

                Just changes ->
                    DiffPackages changes

        ( Just (Elm.Project.Application _), (Elm.Project.Package _) as newProject ) ->
            ReloadDependenciesEntirely newProject

        ( Just (Elm.Project.Package _), (Elm.Project.Application _) as newProject ) ->
            ReloadDependenciesEntirely newProject


diffSourceDirectories : List Path -> List Path -> { added : List Path, removed : List Path }
diffSourceDirectories basePrevious baseAfter =
    let
        previous : List Path
        previous =
            List.map normalizeDirPath basePrevious

        after : List Path
        after =
            List.map normalizeDirPath baseAfter
    in
    { added = List.filter (\dir -> not (List.member dir previous)) after
    , removed = List.filter (\dir -> not (List.member dir after)) previous
    }


normalizeDirPath : Path -> Path
normalizeDirPath path =
    if String.endsWith "/" path then
        String.dropRight 1 path

    else
        path


diffDependencies : List ( Elm.Package.Name, a ) -> List ( Elm.Package.Name, a ) -> Maybe { added : List ( Elm.Package.Name, a ), removed : List Elm.Package.Name }
diffDependencies previous after =
    let
        added : List ( Elm.Package.Name, a )
        added =
            List.filter (\( name, _ ) -> not (List.any (\( name_, _ ) -> name == name_) previous)) after

        removed : List ( Elm.Package.Name, a )
        removed =
            List.filter (\( name, _ ) -> not (List.any (\( name_, _ ) -> name == name_) after)) previous
    in
    if List.isEmpty added && List.isEmpty removed then
        Nothing

    else
        Just { added = added, removed = List.map Tuple.first removed }


fetchAddedSourceDirectories : List Path -> List (TCmd Msg)
fetchAddedSourceDirectories sourceDirectories =
    List.map fetchElmFiles sourceDirectories


removeSourceDirectories : List Path -> Project -> Project
removeSourceDirectories removed previousProject =
    List.foldl
        (\{ path } p ->
            if List.any (\removedDir -> String.startsWith removedDir path) removed then
                Project.removeModule path p

            else
                p
        )
        previousProject
        (Project.modules previousProject)


fetchAddedDependencies : Options -> ElmJsonDependencyChanges -> List (TCmd Msg) -> List (TCmd Msg)
fetchAddedDependencies options dependencies tasks =
    case dependencies of
        NoDependencyChanges ->
            tasks

        DiffApplication packages ->
            addDepsFromVersion options packages.added tasks

        DiffPackages packages ->
            addDepsFromConstraint options packages.added tasks

        ReloadDependenciesEntirely elmJson ->
            case elmJson of
                Elm.Project.Application application ->
                    tasks
                        |> addDepsFromVersion options application.depsDirect
                        |> addDepsFromVersion options application.depsIndirect
                        |> addDepsFromVersion options application.testDepsDirect
                        |> addDepsFromVersion options application.testDepsIndirect

                Elm.Project.Package package ->
                    tasks
                        |> addDepsFromConstraint options package.deps
                        |> addDepsFromConstraint options package.testDeps


removeDependencies : ElmJsonDependencyChanges -> Project -> Project
removeDependencies dependencies previousProject =
    case dependencies of
        NoDependencyChanges ->
            previousProject

        DiffApplication { removed } ->
            List.foldl
                (\name p -> Project.removeDependency (Elm.Package.toString name) p)
                previousProject
                removed

        DiffPackages { removed } ->
            List.foldl
                (\name p -> Project.removeDependency (Elm.Package.toString name) p)
                previousProject
                removed

        ReloadDependenciesEntirely _ ->
            Project.removeDependencies previousProject


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


fetchElmFile : Path -> TCmd Msg
fetchElmFile filePath =
    Fs.readTextFile filePath
        |> TTask.attempt (ReceivedElmFile filePath)


fetchSuppressionFile : Path -> TCmd Msg
fetchSuppressionFile filePath =
    Fs.readTextFile filePath
        |> TTask.attempt (ReceivedSuppressedErrorsFile filePath)


fetchElmJson : TCmd Msg
fetchElmJson =
    readTextFile (\_ -> ReceivedElmJson) elmJsonPath


fetchReadme : TCmd Msg
fetchReadme =
    readTextFile (\_ -> ReceivedReadme) readmePath


elmJsonPath : Path
elmJsonPath =
    "elm.json"


readmePath : Path
readmePath =
    "README.md"


fetchSuppressionFiles : Path -> TCmd Msg
fetchSuppressionFiles suppressedDirectory =
    Fs.walkTree suppressedDirectory (Just "*.json") FsData.Any
        |> TTask.map
            (\files ->
                -- Remove leading "./"
                List.map (String.dropLeft 2) files
            )
        |> TTask.attempt (ReceivedSuppressedErrorsList suppressedDirectory)


fetchElmFiles : Path -> TCmd Msg
fetchElmFiles directory =
    Fs.walkTree directory (Just "*.elm") FsData.Any
        |> TTask.map (\files -> List.map (Path.join2 directory) files)
        |> TTask.attempt (ReceivedElmFileList directory)


fetchDependency : Options -> String -> String -> TCmd Msg
fetchDependency options packageName packageVersion =
    TTask.map2 (\elmJson docsJson -> { elmJson = elmJson, docsJson = docsJson })
        (findOrDownloadPackageFile options packageName packageVersion "elm.json")
        (findOrDownloadPackageFile options packageName packageVersion "docs.json")
        |> TTask.attempt (ReceivedDependency packageName)


findOrDownloadPackageFile : Options -> String -> String -> String -> TTask FsError File
findOrDownloadPackageFile options packageName packageVersion fileName =
    let
        path : Path
        path =
            Path.join [ options.packagesLocation, packageName, packageVersion, fileName ]
    in
    Fs.readTextFile path
        |> TTask.onError
            (\error ->
                if options.offline then
                    TTask.fail error

                else
                    -- TODO Try to download the package like the Elm compiler would, not just a single file
                    readFromPackagesWebsite packageName packageVersion fileName
                        |> TTask.mapError (\_ -> error)
            )
        |> TTask.map (\source -> { path = path, source = source })


readFromPackagesWebsite : String -> String -> String -> TTask () String
readFromPackagesWebsite packageName packageVersion fileName =
    Http.get ("https://package.elm-lang.org/packages/" ++ packageName ++ "/" ++ packageVersion ++ "" ++ fileName)


fetchRuleLinks : { options | reviewFolder : Path, packagesLocation : Path } -> TCmd Msg
fetchRuleLinks { reviewFolder, packagesLocation } =
    Fs.readTextFile (Path.join2 reviewFolder "elm.json")
        |> TTask.andThen
            (\elmJson ->
                case Decode.decodeString Elm.Project.decoder elmJson of
                    Ok (Elm.Project.Application { depsDirect, depsIndirect }) ->
                        TTask.mapAllAndFold
                            (readElmJson packagesLocation)
                            (\deps dict -> List.foldl (\( name, dep ) d -> Dict.insert name dep d) dict deps)
                            Dict.empty
                            (depsDirect ++ depsIndirect)

                    _ ->
                        TTask.succeed Dict.empty
            )
        |> TTask.onError (\_ -> TTask.succeed Dict.empty)
        |> TTask.perform (\links -> ReceivedRuleLinks { links = links, fromCache = False })


readElmJson : Path -> ( Elm.Package.Name, Elm.Version.Version ) -> TTask x (List ( String, String ))
readElmJson packagesLocation ( rawPackageName, rawPackageVersion ) =
    let
        packageName : String
        packageName =
            Elm.Package.toString rawPackageName

        packageVersion : String
        packageVersion =
            Elm.Version.toString rawPackageVersion
    in
    Path.join [ packagesLocation, packageName, packageVersion, "elm.json" ]
        |> Fs.readTextFile
        |> TTask.map
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
        |> TTask.onError (\_ -> TTask.succeed [])


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


readTextFile : (String -> Result FsError String -> msg) -> String -> TCmd msg
readTextFile toMsg path =
    Fs.readTextFile path
        |> TTask.attempt (\result -> toMsg path result)


subscriptions : Options -> Model -> TSub Msg
subscriptions options (Model model) =
    TSub.batch
        [ watchPath
            { path = elmJsonPath
            , toMsg = \_ -> GotProjectElmJsonWatchEvent
            , recursive = False
            , eventMask = 3
            }
        , watchPath
            { path = readmePath
            , toMsg = GotProjectReadmeWatchEvent
            , recursive = False
            , eventMask = 7
            }
        , watchSourceDirectories options model
        , watchSuppressedFiles options
        ]


watchSourceDirectories : Options -> ModelData -> TSub Msg
watchSourceDirectories options model =
    case Project.elmJson model.project of
        Just elmJson ->
            case elmFilesToFetch elmJson.project options.directoriesToAnalyze of
                Ok targets ->
                    TSub.mapBatch
                        (\path ->
                            watchPath
                                { path = path
                                , toMsg = GotSourceFileWatchEvent
                                , recursive = options.directoriesToAnalyze == Nothing || not (String.endsWith ".elm" path)
                                , eventMask = 15
                                }
                        )
                        targets

                Err _ ->
                    TSub.none

        Nothing ->
            TSub.none


watchSuppressedFiles : Options -> TSub Msg
watchSuppressedFiles options =
    watchPath
        { path = SuppressedErrors.suppressedFolder options
        , toMsg = GotSuppressedFileWatchEvent
        , recursive = False -- TODO Should this be True?
        , eventMask = 7
        }


watchPath : { toMsg : FileEvent -> Msg, path : Path, recursive : Bool, eventMask : Int } -> TSub Msg
watchPath { toMsg, path, recursive, eventMask } =
    FileWatcher.watch
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

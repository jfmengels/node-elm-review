module Wrapper.Review exposing
    ( Model, init
    , Msg, update, subscriptions
    )

{-|

@docs Model, init
@docs Msg, update, subscriptions

-}

import Elm.Project
import Elm.Review.Testable.Cli as Cli
import Elm.Review.Testable.Cmd as TCmd
import Elm.Review.Testable.FileWatchData exposing (FileEvent)
import Elm.Review.Testable.FileWatcher as FileWatcher
import Elm.Review.Testable.Fs as Fs
import Elm.Review.Testable.FsData as FsData exposing (FsError(..))
import Elm.Review.Testable.Internal exposing (TCmd, TSub, TTask)
import Elm.Review.Testable.Process as Process
import Elm.Review.Testable.ProcessData as ProcessData exposing (ProcessId)
import Elm.Review.Testable.TSub as TSub
import Elm.Review.Testable.TTask as TTask
import ElmReview.Color exposing (Color(..))
import ElmReview.Path as Path exposing (Path)
import ElmReview.Problem as Problem exposing (Problem, ProblemSimple)
import ElmReview.ReportMode as ReportMode
import Wrapper.Build as Build
import Wrapper.Options as Options exposing (ReviewOptions)
import Wrapper.OutputTarget as OutputTarget
import Wrapper.ProjectPaths as ProjectPaths exposing (ProjectPaths)


type Model
    = Model ModelData


type alias ModelData =
    { options : ReviewOptions
    , buildId : BuildId
    , pid : Maybe ProcessId
    , watch : Maybe (TSub Msg)
    }


type BuildId
    = BuildId Int


incrementBuild : BuildId -> BuildId
incrementBuild (BuildId n) =
    BuildId (n + 1)


type Msg
    = BuildCompleted BuildId (Result Problem.Exit Build.BuildData)
    | SpawnedReviewProcess (Result Problem.Exit ProcessId)
    | ReviewProcessEnded ProcessId (Result Problem.Exit Int)
    | ConfigElmJsonWasModified
    | ConfigSourceFileWasModified FileEvent


init : ReviewOptions -> ( Model, TCmd Msg )
init options =
    let
        buildId : BuildId
        buildId =
            BuildId 0
    in
    ( Model
        { buildId = buildId
        , options = options
        , pid = Nothing
        , watch = Nothing
        }
    , startBuild options
        |> TTask.onError (\problem -> Problem.exitOnUnrecoverable (formatOptions options) problem)
        |> TTask.attempt (BuildCompleted buildId)
    )


verifyElmJsonExists : ProjectPaths -> TTask Problem ()
verifyElmJsonExists projectPaths =
    let
        elmJsonPath : Path
        elmJsonPath =
            Path.join2 (ProjectPaths.projectRoot projectPaths) "elm.json"
    in
    Fs.stat elmJsonPath
        |> TTask.map (\_ -> ())
        |> TTask.mapError
            (\((FsError errno _) as error) ->
                let
                    problem : ProblemSimple
                    problem =
                        case errno of
                            FsData.ENOENT ->
                                { title = "ELM.JSON NOT FOUND"
                                , message = \c -> "I could not find the " ++ c Cyan "elm.json" ++ " of the project to review. I was looking for it at\n\n    " ++ c Yellow elmJsonPath ++ """

Since you specified this path, I'm assuming that you misconfigured the CLI's arguments."""
                                }

                            _ ->
                                { title = "PROBLEM READING ELM.JSON"
                                , message = \c -> "I was trying to read " ++ c Yellow elmJsonPath ++ " but encountered a problem:\n\n" ++ FsData.errorToString error
                                }
                in
                problem
                    |> Problem.from Problem.Recoverable
                    |> Problem.withPath elmJsonPath
            )


update : Msg -> Model -> ( Model, TCmd Msg )
update msg (Model model) =
    updateHelp msg model
        |> Tuple.mapFirst Model


formatOptions : ReviewOptions -> Problem.FormatOptions {}
formatOptions options =
    { color = options.color
    , reportMode = options.reportMode
    , debug = options.debug
    , attemptFutureRecovery = options.watchConfig
    }


updateHelp : Msg -> ModelData -> ( ModelData, TCmd Msg )
updateHelp msg model =
    case msg of
        BuildCompleted buildId result ->
            if buildId /= model.buildId then
                ( model, TCmd.none )

            else
                case result of
                    Ok { elmJsonPath, reviewElmJson, reviewAppPath, packagesLocation, appHash } ->
                        ( if model.options.watchConfig then
                            case model.options.reviewProject of
                                Options.Local reviewFolder ->
                                    let
                                        watcher : TSub Msg
                                        watcher =
                                            watchConfig reviewFolder reviewElmJson
                                    in
                                    { model | watch = Just watcher }

                                Options.Remote _ ->
                                    model

                          else
                            model
                        , runReviewProcess model.options
                            { reviewAppPath = reviewAppPath
                            , reviewElmJson = reviewElmJson
                            , reviewFolder = Path.dirname elmJsonPath
                            , resultCacheFolder = ProjectPaths.resultCacheFolder model.options.projectPaths appHash
                            , packagesLocation = packagesLocation
                            }
                            |> TTask.onError (\problem -> Problem.exitOnUnrecoverable (formatOptions model.options) problem)
                            |> TTask.attempt SpawnedReviewProcess
                        )

                    Err exit ->
                        ( model
                        , Problem.exit exit
                        )

        SpawnedReviewProcess result ->
            case result of
                Ok pid ->
                    ( { model | pid = Just pid }
                    , Process.wait pid
                        |> TTask.mapError (\error -> Problem.unexpectedError "when waiting for the review application's results" (ProcessData.errorToString error))
                        |> TTask.map .exitCode
                        |> TTask.onError (\problem -> Problem.exitOnUnrecoverable (formatOptions model.options) problem)
                        |> TTask.attempt (ReviewProcessEnded pid)
                    )

                Err exit ->
                    ( model
                    , Problem.exit exit
                    )

        ReviewProcessEnded pid result ->
            if model.pid == Just pid then
                case result of
                    Ok exitCode ->
                        ( model
                        , Cli.exit exitCode
                        )

                    Err exit ->
                        ( model
                        , Problem.exit exit
                        )

            else
                ( model, TCmd.none )

        ConfigElmJsonWasModified ->
            -- TODO Wait a bit before doing anything, we might be in the middle of a rebase
            -- TODO Check if the important parts of file has changed
            restartBuild model

        ConfigSourceFileWasModified fileEvent ->
            if String.endsWith ".elm" fileEvent.path then
                -- TODO Wait a bit before doing anything, we might be in the middle of a rebase
                restartBuild model

            else
                ( model, TCmd.none )


restartBuild : ModelData -> ( ModelData, TCmd Msg )
restartBuild model =
    let
        buildId : BuildId
        buildId =
            incrementBuild model.buildId
    in
    ( { model | buildId = buildId, pid = Nothing }
    , printRestartMessage model.options.reportMode
        |> TTask.andThen (\() -> killRunningApp model.pid)
        |> TTask.andThen (\() -> startBuild model.options)
        |> TTask.onError (\problem -> Problem.exitOnUnrecoverable (formatOptions model.options) problem)
        |> TTask.attempt (BuildCompleted buildId)
    )


printRestartMessage : ReportMode.ReportMode -> TTask x ()
printRestartMessage reportMode =
    case reportMode of
        ReportMode.HumanReadable ->
            Cli.printlnStdoutTask "Your configuration has changed. Restarting elm-review with the new one."

        ReportMode.Json ->
            TTask.succeed ()

        ReportMode.NDJson ->
            TTask.succeed ()


killRunningApp : Maybe ProcessId -> TTask x ()
killRunningApp currentPid =
    case currentPid of
        Just pid ->
            -- TODO Send softer signal that waits until any file writes are done and exits.
            --      Requires a Subscription in the review app that listens to signals
            Process.kill pid 9
                |> TTask.onError (\_ -> TTask.succeed ())

        Nothing ->
            TTask.succeed ()


startBuild : ReviewOptions -> TTask.TTask Problem Build.BuildData
startBuild options =
    verifyElmJsonExists options.projectPaths
        |> TTask.andThen (\() -> Build.build options)


type alias RunReviewOptions =
    { reviewAppPath : Path
    , reviewElmJson : Elm.Project.ApplicationInfo
    , reviewFolder : Path
    , resultCacheFolder : Path
    , packagesLocation : Path
    }


runReviewProcess : ReviewOptions -> RunReviewOptions -> TTask Problem ProcessId
runReviewProcess options runReviewOptions =
    case options.outputTarget of
        OutputTarget.JavaScriptTarget ->
            runReviewProcessWithNodeJs options runReviewOptions

        OutputTarget.ElmRunTarget ->
            runReviewProcessWithElmRun options runReviewOptions


runReviewProcessWithNodeJs : ReviewOptions -> RunReviewOptions -> TTask Problem ProcessId
runReviewProcessWithNodeJs options { reviewAppPath, reviewElmJson, reviewFolder, resultCacheFolder, packagesLocation } =
    let
        reviewAppFlags : List String
        reviewAppFlags =
            resultCacheFolder
                :: ("--review-folder=" ++ reviewFolder)
                :: ("--packages-location=" ++ packagesLocation)
                :: options.reviewAppFlags
    in
    Process.spawn
        "node"
        { args = Path.join2 options.binaryRoot "lib/elm-app-worker2.js" :: reviewAppPath :: reviewAppFlags
        , cwd = Just (ProjectPaths.projectRoot options.projectPaths)
        , env = Nothing
        , stdin = ProcessData.InheritStdin
        , stdout = ProcessData.InheritStdout
        , stderr = ProcessData.InheritStderr
        }
        |> TTask.mapError
            (\err ->
                Problem.unexpectedError "when running the review application" (ProcessData.errorToString err)
                    |> Problem.withPath reviewAppPath
            )


runReviewProcessWithElmRun : ReviewOptions -> RunReviewOptions -> TTask Problem ProcessId
runReviewProcessWithElmRun options { reviewAppPath, reviewElmJson, reviewFolder, packagesLocation } =
    let
        reviewAppFlags : List String
        reviewAppFlags =
            ("--review-folder=" ++ reviewFolder)
                :: ("--packages-location=" ++ packagesLocation)
                :: options.reviewAppFlags

        ( cmd, args ) =
            if options.debug then
                -- TODO Get host-cli from somewhere?
                ( "host-cli"
                , "-v" :: "--trust" :: reviewAppPath :: reviewAppFlags
                )

            else
                ( reviewAppPath, reviewAppFlags )
    in
    Process.spawn
        cmd
        { args = args
        , cwd = Just (ProjectPaths.projectRoot options.projectPaths)
        , env = Nothing
        , stdin = ProcessData.InheritStdin
        , stdout = ProcessData.InheritStdout
        , stderr = ProcessData.InheritStderr
        }
        |> TTask.mapError
            (\err ->
                Problem.unexpectedError "when running the review application" (ProcessData.errorToString err)
                    |> Problem.withPath reviewAppPath
            )


subscriptions : Model -> TSub Msg
subscriptions (Model model) =
    case model.watch of
        Just sub ->
            sub

        Nothing ->
            TSub.none


watchConfig : Path -> Elm.Project.ApplicationInfo -> TSub Msg
watchConfig reviewFolder reviewElmJson =
    watchElmJson reviewFolder
        :: List.map (\dir -> watchSourceDirectory (Path.join2 reviewFolder dir)) reviewElmJson.dirs
        |> TSub.batch


watchElmJson : Path -> TSub Msg
watchElmJson reviewFolder =
    FileWatcher.watch
        { path = Path.join2 reviewFolder "elm.json"
        , excludePaths = []
        , recursive = False
        , coalesceMs = 100
        , eventMask = 2
        }
        (\_ -> ConfigElmJsonWasModified)


watchSourceDirectory : Path -> TSub Msg
watchSourceDirectory directory =
    FileWatcher.watch
        { path = directory
        , excludePaths = []
        , recursive = True
        , coalesceMs = 100
        , eventMask = 2
        }
        ConfigSourceFileWasModified

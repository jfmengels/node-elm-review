module Wrapper.Review exposing
    ( Model, init
    , Msg, update, subscriptions
    )

{-|

@docs Model, init
@docs Msg, update, subscriptions

-}

import Capabilities exposing (Console, FileWatcher)
import Elm.Project
import Elm.Review.Testable.Cli as Cli
import Elm.Review.Testable.Cmd as TCmd
import Elm.Review.Testable.FileWatchData exposing (FileEvent)
import Elm.Review.Testable.FileWatcher as FileWatcher
import Elm.Review.Testable.Fs as Fs
import Elm.Review.Testable.FsData as FsData
import Elm.Review.Testable.Internal exposing (TCmd, TSub, TTask)
import Elm.Review.Testable.Process as Process
import Elm.Review.Testable.ProcessData as Process
import Elm.Review.Testable.TSub as TSub
import Elm.Review.Testable.TTask as TTask
import ElmReview.Color exposing (Color(..))
import ElmReview.Path as Path exposing (Path)
import ElmReview.Problem as Problem exposing (Problem, ProblemSimple)
import ElmReview.ReportMode as ReportMode
import ElmRun.FsExtra as FsExtra
import ElmRun.ProcessExtra as ProcessExtra
import Worker.Process exposing (ProcessId)
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
    = BuildCompleted BuildId (Result Problem Build.BuildData)
    | SpawnedReviewProcess (Result Problem ProcessId)
    | ReviewProcessEnded ProcessId (Result Problem Process.Completed)
    | ConfigElmJsonWasModified
    | ConfigSourceFileWasModified FileEvent
    | KilledReviewProcess


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
    , startBuild options buildId
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
            (\error ->
                let
                    problem : ProblemSimple
                    problem =
                        case error of
                            FsData.NotFound _ ->
                                { title = "ELM.JSON NOT FOUND"
                                , message = \c -> "I could not find the " ++ c Cyan "elm.json" ++ " of the project to review. I was looking for it at\n\n    " ++ c Yellow elmJsonPath ++ """

Since you specified this path, I'm assuming that you misconfigured the CLI's arguments."""
                                }

                            _ ->
                                { title = "PROBLEM READING ELM.JSON"
                                , message = \c -> "I was trying to read " ++ c Yellow elmJsonPath ++ " but encountered a problem:\n\n" ++ FsExtra.errorToString error
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


stopBecauseOfProblem : ModelData -> Problem -> TCmd msg
stopBecauseOfProblem model problem =
    Problem.stop
        { color = model.options.color
        , reportMode = model.options.reportMode
        , debug = model.options.debug
        , attemptFutureRecovery = model.options.watchConfig
        }
        problem


updateHelp : Msg -> ModelData -> ( ModelData, TCmd Msg )
updateHelp msg model =
    case msg of
        BuildCompleted buildId result ->
            if buildId /= model.buildId then
                ( model, TCmd.none )

            else
                case result of
                    Ok { elmJsonPath, reviewElmJson, reviewAppPath, packagesLocation } ->
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
                            , packagesLocation = packagesLocation
                            }
                            |> TTask.attempt SpawnedReviewProcess
                        )

                    Err problem ->
                        ( model
                        , stopBecauseOfProblem model problem
                        )

        SpawnedReviewProcess result ->
            case result of
                Ok pid ->
                    ( { model | pid = Just pid }
                    , Process.wait pid
                        |> TTask.mapError (\error -> Debug.todo ("Spawn error " ++ ProcessExtra.errorToString error))
                        |> TTask.attempt (ReviewProcessEnded pid)
                    )

                Err problem ->
                    ( model
                    , stopBecauseOfProblem model problem
                    )

        ReviewProcessEnded pid result ->
            if model.pid == Just pid then
                case result of
                    Ok completed ->
                        ( model
                        , Cli.exit completed.exitCode
                        )

                    Err problem ->
                        ( model
                        , stopBecauseOfProblem model problem
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

        KilledReviewProcess ->
            ( model, TCmd.none )


restartBuild : ModelData -> ( ModelData, TCmd Msg )
restartBuild model =
    let
        buildId : BuildId
        buildId =
            incrementBuild model.buildId
    in
    ( { model | buildId = buildId, pid = Nothing }
    , TCmd.batch
        [ case model.options.reportMode of
            ReportMode.HumanReadable ->
                Cli.printlnStdout "Your configuration has changed. Restarting elm-review with the new one."

            ReportMode.Json ->
                TCmd.none

            ReportMode.NDJson ->
                TCmd.none
        , startBuild model.options buildId
        , case model.pid of
            Just pid ->
                -- TODO Send softer signal that waits until any file writes are done and exits.
                --      Requires a Subscription in the review app that listens to signals
                Process.kill pid 9
                    |> TTask.attempt (\_ -> KilledReviewProcess)

            Nothing ->
                TCmd.none
        ]
    )


startBuild : ReviewOptions -> BuildId -> TCmd Msg
startBuild options buildId =
    verifyElmJsonExists options.projectPaths
        |> TTask.andThen (\() -> Build.build options)
        |> TTask.attempt (BuildCompleted buildId)


type alias RunReviewOptions =
    { reviewAppPath : Path
    , reviewElmJson : Elm.Project.ApplicationInfo
    , reviewFolder : Path
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
runReviewProcessWithNodeJs options { reviewAppPath, reviewElmJson, reviewFolder, packagesLocation } =
    let
        reviewAppFlags : List String
        reviewAppFlags =
            ("--review-folder=" ++ reviewFolder)
                :: ("--packages-location=" ++ packagesLocation)
                :: options.reviewAppFlags
    in
    Process.spawn
        "node"
        { args = Path.join2 options.binaryRoot "lib/elm-app-worker2.js" :: reviewAppPath :: reviewAppFlags
        , cwd = Just (ProjectPaths.projectRoot options.projectPaths)
        , env = Nothing
        , stdin = Process.InheritStdin
        , stdout = Process.InheritStdout
        , stderr = Process.InheritStderr
        }
        |> TTask.mapError
            (\err ->
                Problem.unexpectedError "when running the review application" (ProcessExtra.errorToString err)
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
        , stdin = Process.InheritStdin
        , stdout = Process.InheritStdout
        , stderr = Process.InheritStderr
        }
        |> TTask.mapError
            (\err ->
                Problem.unexpectedError "when running the review application" (ProcessExtra.errorToString err)
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
        (Path.join2 reviewFolder "elm.json")
        { excludePaths = []
        , recursive = False
        , coalesceMs = 100
        , eventMask = 2
        }
        (\_ -> ConfigElmJsonWasModified)


watchSourceDirectory : Path -> TSub Msg
watchSourceDirectory directory =
    FileWatcher.watch
        directory
        { excludePaths = []
        , recursive = True
        , coalesceMs = 100
        , eventMask = 2
        }
        ConfigSourceFileWasModified


watchPermission : () -> Maybe FileWatcher
watchPermission () =
    -- TODO Get FileWatcher permission from somewhere
    Nothing

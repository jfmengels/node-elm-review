module Wrapper.Review exposing
    ( Model, init
    , Msg, update, subscriptions
    )

{-|

@docs Model, init
@docs Msg, update, subscriptions

-}

import Capabilities exposing (Console, FileWatcher)
import Cli
import Elm.Project
import ElmReview.Color exposing (Color(..))
import ElmReview.Path as Path exposing (Path)
import ElmReview.Problem as Problem exposing (Problem, ProblemSimple)
import ElmReview.ReportMode as ReportMode
import ElmRun.FsExtra as FsExtra
import ElmRun.ProcessExtra as ProcessExtra
import Fs exposing (FileSystem)
import Os exposing (ProcessCapability)
import Os.Process as Process
import Task exposing (Task)
import Worker.FileWatcher as FileWatcher exposing (FileEvent)
import Worker.Process exposing (ProcessId)
import Wrapper.Build as Build
import Wrapper.Options as Options exposing (ReviewOptions)
import Wrapper.ProjectPaths as ProjectPaths exposing (ProjectPaths)


type Model
    = Model ModelData


type alias ModelData =
    { stdout : Console
    , stderr : Console
    , fs : FileSystem
    , os : ProcessCapability
    , options : ReviewOptions
    , buildId : BuildId
    , pid : Maybe ProcessId
    , watch : Maybe (Sub Msg)
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


init : { env | stdout : Console, stderr : Console } -> { capabilities | fs : FileSystem, os : ProcessCapability } -> ReviewOptions -> ( Model, Cmd Msg )
init { stdout, stderr } { fs, os } options =
    let
        buildId : BuildId
        buildId =
            BuildId 0
    in
    ( Model
        { stdout = stdout
        , stderr = stderr
        , fs = fs
        , os = os
        , buildId = buildId
        , options = options
        , pid = Nothing
        , watch = Nothing
        }
    , startBuild fs os options buildId
    )


verifyElmJsonExists : FileSystem -> ProjectPaths -> Task Problem ()
verifyElmJsonExists fs projectPaths =
    let
        elmJsonPath : Path
        elmJsonPath =
            Path.join2 (ProjectPaths.projectRoot projectPaths) "elm.json"
    in
    Fs.stat fs elmJsonPath
        |> Task.map (\_ -> ())
        |> Task.mapError
            (\error ->
                let
                    problem : ProblemSimple
                    problem =
                        case error of
                            Fs.NotFound _ ->
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


update : Msg -> Model -> ( Model, Cmd Msg )
update msg (Model model) =
    updateHelp msg model
        |> Tuple.mapFirst Model


stopBecauseOfProblem : ModelData -> Problem -> Cmd msg
stopBecauseOfProblem model problem =
    Problem.stop
        model.stderr
        { color = model.options.color
        , reportMode = model.options.reportMode
        , debug = model.options.debug
        , attemptFutureRecovery = model.options.watchConfig
        }
        problem


updateHelp : Msg -> ModelData -> ( ModelData, Cmd Msg )
updateHelp msg model =
    case msg of
        BuildCompleted buildId result ->
            if buildId /= model.buildId then
                ( model, Cmd.none )

            else
                case result of
                    Ok { elmJsonPath, reviewElmJson, reviewAppPath, packagesLocation } ->
                        ( if model.options.watchConfig then
                            case model.options.reviewProject of
                                Options.Local reviewFolder ->
                                    case watchPermission () of
                                        Just fileWatcher ->
                                            let
                                                watcher : Sub Msg
                                                watcher =
                                                    watchConfig fileWatcher reviewFolder reviewElmJson
                                            in
                                            { model | watch = Just watcher }

                                        Nothing ->
                                            model

                                Options.Remote _ ->
                                    model

                          else
                            model
                        , runReviewProcess model
                            { reviewAppPath = reviewAppPath
                            , reviewElmJson = reviewElmJson
                            , reviewFolder = Path.dirname elmJsonPath
                            , packagesLocation = packagesLocation
                            }
                        )

                    Err problem ->
                        ( model
                        , stopBecauseOfProblem model problem
                        )

        SpawnedReviewProcess result ->
            case result of
                Ok pid ->
                    ( { model | pid = Just pid }
                    , Process.wait model.os pid
                        |> Task.mapError (\error -> Debug.todo ("Spawn error " ++ ProcessExtra.errorToString error))
                        |> Task.attempt (ReviewProcessEnded pid)
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
                ( model, Cmd.none )

        ConfigElmJsonWasModified ->
            -- TODO Wait a bit before doing anything, we might be in the middle of a rebase
            -- TODO Check if the important parts of file has changed
            restartBuild model

        ConfigSourceFileWasModified fileEvent ->
            if String.endsWith ".elm" fileEvent.path then
                -- TODO Wait a bit before doing anything, we might be in the middle of a rebase
                restartBuild model

            else
                ( model, Cmd.none )

        KilledReviewProcess ->
            ( model, Cmd.none )


restartBuild : ModelData -> ( ModelData, Cmd Msg )
restartBuild model =
    let
        buildId : BuildId
        buildId =
            incrementBuild model.buildId
    in
    ( { model | buildId = buildId, pid = Nothing }
    , Cmd.batch
        [ case model.options.reportMode of
            ReportMode.HumanReadable ->
                Cli.println model.stdout "Your configuration has changed. Restarting elm-review with the new one."

            ReportMode.Json ->
                Cmd.none

            ReportMode.NDJson ->
                Cmd.none
        , startBuild model.fs model.os model.options buildId
        , case model.pid of
            Just pid ->
                -- TODO Send softer signal that waits until any file writes are done and exits.
                --      Requires a Subscription in the review app that listens to signals
                Process.kill model.os pid 9
                    |> Task.attempt (\_ -> KilledReviewProcess)

            Nothing ->
                Cmd.none
        ]
    )


startBuild : FileSystem -> ProcessCapability -> ReviewOptions -> BuildId -> Cmd Msg
startBuild fs os options buildId =
    verifyElmJsonExists fs options.projectPaths
        |> Task.andThen (\() -> Build.build fs os options)
        |> Task.attempt (BuildCompleted buildId)


type alias RunReviewOptions =
    { reviewAppPath : Path
    , reviewElmJson : Elm.Project.ApplicationInfo
    , reviewFolder : Path
    , packagesLocation : Path
    }


runReviewProcess : ModelData -> RunReviewOptions -> Cmd Msg
runReviewProcess { os, options } { reviewAppPath, reviewElmJson, reviewFolder, packagesLocation } =
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
    ProcessExtra.runButFailOnError os
        cmd
        { args = args
        , cwd = Just (ProjectPaths.projectRoot options.projectPaths)
        , env = Nothing
        , stdin = Process.InheritStdin
        , stdout = Process.InheritStdout
        , stderr = Process.InheritStderr
        }
        |> Task.mapError
            (\error ->
                case error of
                    ProcessExtra.ProcessError processError ->
                        Problem.unexpectedError "when running the review application" (ProcessExtra.errorToString processError)
                            |> Problem.withPath reviewAppPath

                    ProcessExtra.CommandNotFound ->
                        { title = "COMMAND NOT FOUND"

                        -- TODO Make "run not found" helper more helpful, e.g. by adding installations details.
                        , message = \c -> "I could not find the " ++ c Yellow "run" ++ " executable. Is it installed on your system?"
                        }
                            |> Problem.from Problem.Recoverable

                    ProcessExtra.CommandFailed completed ->
                        Problem.unexpectedError "when running the review application" (Maybe.withDefault "No output from host-cli" completed.stderr)
            )
        |> Task.map .pid
        |> Task.attempt SpawnedReviewProcess


subscriptions : Model -> Sub Msg
subscriptions (Model model) =
    case model.watch of
        Just sub ->
            sub

        Nothing ->
            Sub.none


watchConfig : FileWatcher -> Path -> Elm.Project.ApplicationInfo -> Sub Msg
watchConfig fileWatcher reviewFolder reviewElmJson =
    watchElmJson fileWatcher reviewFolder
        :: List.map (\dir -> watchSourceDirectory fileWatcher (Path.join2 reviewFolder dir)) reviewElmJson.dirs
        |> Sub.batch


watchElmJson : FileWatcher -> Path -> Sub Msg
watchElmJson fileWatcher reviewFolder =
    FileWatcher.watch
        fileWatcher
        (Path.join2 reviewFolder "elm.json")
        { excludePaths = []
        , recursive = False
        , coalesceMs = 100
        , eventMask = 2
        }
        (\_ -> ConfigElmJsonWasModified)


watchSourceDirectory : FileWatcher -> Path -> Sub Msg
watchSourceDirectory fileWatcher directory =
    FileWatcher.watch
        fileWatcher
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

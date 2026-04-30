module Wrapper.Review exposing
    ( Model, init
    , Msg, update, subscriptions
    )

{-|

@docs Model, init
@docs Msg, update, subscriptions

-}

import Capabilities exposing (Console)
import Cli exposing (Env)
import Elm.Project
import ElmReview.Color exposing (Color(..))
import ElmReview.Path as Path exposing (Path)
import ElmReview.Problem as Problem exposing (FormatOptions, Problem, ProblemSimple)
import ElmRun.FsExtra as FsExtra
import ElmRun.OsExtra
import Fs exposing (FileSystem, FsError)
import Os exposing (ProcessCapability)
import Os.Process as Process exposing (ProcessError)
import Task exposing (Task)
import Worker.FileWatcher as FileWatcher exposing (FileEvent)
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
    }


type Msg
    = BuildCompleted (Result Problem Build.BuildData)
    | ReviewProcessEnded (Result Problem Process.Completed)
    | GotElmJsonWatchEvent FileEvent


init : { env | stdout : Console, stderr : Console } -> { capabilities | fs : FileSystem, os : ProcessCapability } -> ReviewOptions -> ( Model, Cmd Msg )
init { stdout, stderr } { fs, os } options =
    let
        -- TODO Get from somewhere
        elmHomePath : String
        elmHomePath =
            "/Users/m1/.elm"
    in
    ( Model
        { stdout = stdout
        , stderr = stderr
        , fs = fs
        , os = os
        , options = options
        }
    , startBuild fs os options elmHomePath
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
                    |> Problem.from
                    |> Problem.withPath elmJsonPath
            )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg (Model model) =
    updateHelp msg model
        |> Tuple.mapFirst Model


updateHelp : Msg -> ModelData -> ( ModelData, Cmd Msg )
updateHelp msg model =
    case msg of
        BuildCompleted result ->
            case result of
                Ok { elmJsonPath, reviewElmJson, reviewAppPath, packagesLocation } ->
                    ( model
                    , runReviewProcess model
                        { reviewAppPath = reviewAppPath
                        , reviewElmJson = reviewElmJson
                        , reviewFolder = Path.dirname elmJsonPath
                        , packagesLocation = packagesLocation
                        }
                    )

                Err problem ->
                    ( model
                    , Problem.exit model.stderr model.options problem
                    )

        ReviewProcessEnded result ->
            case result of
                Ok completed ->
                    ( model
                    , Cli.exit completed.exitCode
                    )

                Err problem ->
                    ( model
                    , Problem.exit model.stderr model.options problem
                    )

        GotElmJsonWatchEvent fileEvent ->
            let
                -- TODO Get from somewhere
                elmHomePath : String
                elmHomePath =
                    "/Users/m1/.elm"
            in
            case FileWatcher.toEventType fileEvent.eventType of
                FileWatcher.Modified ->
                    -- TODO Wait a bit before doing anything, we might be in the middle of a rebase
                    -- TODO Check if the important parts of file has changed
                    -- TODO Kill the previous app
                    -- TODO Show a message to the user? (depends on report mode)
                    ( model
                    , startBuild model.fs model.os model.options elmHomePath
                    )

                FileWatcher.Created ->
                    -- TODO Consider file as being modified after a delete
                    ( model, Cmd.none )

                FileWatcher.Deleted ->
                    -- TODO Mark elm.json as temporarily deleted?
                    -- Keep process alive regardless
                    ( model, Cmd.none )

                FileWatcher.Renamed ->
                    -- Can't really be renamed?
                    ( model, Cmd.none )


startBuild : FileSystem -> ProcessCapability -> ReviewOptions -> Path -> Cmd Msg
startBuild fs os options elmHomePath =
    verifyElmJsonExists fs options.projectPaths
        |> Task.andThen (\() -> Build.build fs os options elmHomePath)
        |> Task.attempt BuildCompleted


runReviewProcess :
    ModelData
    ->
        { reviewAppPath : Path
        , reviewElmJson : Elm.Project.ApplicationInfo
        , reviewFolder : Path
        , packagesLocation : Path
        }
    -> Cmd Msg
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
    Process.run os
        cmd
        { args = args
        , cwd = Just (ProjectPaths.projectRoot options.projectPaths)
        , env = Nothing
        , stdin = Process.InheritStdin
        , stdout = Process.InheritStdout
        , stderr = Process.InheritStderr
        }
        |> Task.mapError
            (\err ->
                Problem.unexpectedError "when running the review application" (ElmRun.OsExtra.errorToString err)
                    |> Problem.withPath reviewAppPath
            )
        |> Task.attempt ReviewProcessEnded


subscriptions : Model -> Sub Msg
subscriptions (Model model) =
    if model.options.watchConfig then
        case model.options.reviewProject of
            Options.Local reviewFolder ->
                watchElmJson reviewFolder

            Options.Remote _ ->
                Sub.none

    else
        Sub.none


watchElmJson : Path -> Sub Msg
watchElmJson reviewFolder =
    FileWatcher.watch
        (Debug.todo "watch permission")
        (Path.join2 reviewFolder "elm.json")
        { excludePaths = []
        , recursive = False
        , coalesceMs = 100
        , eventMask = 15
        }
        GotElmJsonWatchEvent

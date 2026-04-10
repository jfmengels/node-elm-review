module Wrapper.Review exposing
    ( Model, init
    , Msg, update
    )

{-|

@docs Model, init
@docs Msg, update

-}

import Capabilities exposing (Console)
import Cli exposing (Env)
import ElmReview.Problem as Problem exposing (FormatOptions, Problem)
import ElmRun.OsExtra
import Fs exposing (FileSystem, FsError)
import Os exposing (ProcessCapability)
import Os.Process as Process exposing (ProcessError)
import Task exposing (Task)
import Wrapper.Build as Build
import Wrapper.Options exposing (ReviewOptions)
import Wrapper.ProjectPaths as ProjectPaths


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
    | ReviewProcessEnded (Result ProcessError Process.Completed)


init : { env | stdout : Console, stderr : Console } -> { capabilities | fs : FileSystem, os : ProcessCapability } -> ReviewOptions -> ( Model, Cmd Msg )
init { stdout, stderr } { fs, os } options =
    ( Model
        { stdout = stdout
        , stderr = stderr
        , fs = fs
        , os = os
        , options = options
        }
    , Build.build fs os options
        |> Task.attempt BuildCompleted
    )


update : Msg -> Model -> Cmd Msg
update msg (Model model) =
    case msg of
        BuildCompleted result ->
            case result of
                Ok { reviewAppPath } ->
                    runReviewProcess model reviewAppPath

                Err problem ->
                    Problem.exit model.stderr model.options problem

        ReviewProcessEnded result ->
            case result of
                Ok completed ->
                    Cli.exit completed.exitCode

                Err err ->
                    Cmd.batch
                        [ Cli.println model.stdout ("error: " ++ ElmRun.OsExtra.errorToString err)
                        , Cli.exit 1
                        ]


runReviewProcess : ModelData -> String -> Cmd Msg
runReviewProcess { os, options } appBinary =
    let
        ( cmd, args ) =
            if options.debug then
                -- TODO Get host-cli from somewhere?
                ( "host-cli"
                , "-v" :: "--trust" :: appBinary :: options.reviewAppFlags
                )

            else
                ( appBinary, options.reviewAppFlags )
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
        |> Task.attempt ReviewProcessEnded

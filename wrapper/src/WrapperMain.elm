module WrapperMain exposing (main)

import Cli exposing (Env)
import Elm.Review.CliVersion as CliVersion
import Fs exposing (FileSystem)
import Os exposing (ProcessCapability)
import Os.Process as Process exposing (ProcessError, defaultSpawnOptions)
import Task
import Wrapper.Build as Build
import Wrapper.Help as Help
import Wrapper.Options exposing (Options)
import Wrapper.Options.Parser as OptionsParser
import Wrapper.Problem as Problem


main : Cli.Program ModelWrapper Msg
main =
    Cli.program
        { init = init
        , update = updateWrapper
        , subscriptions = \_ -> Sub.none
        }


type ModelWrapper
    = Done
    | Running Model


type alias Model =
    { env : Env
    , fs : FileSystem
    , os : ProcessCapability
    , options : Options
    }


type Msg
    = BuildMsg Build.Msg
    | ReviewProcessEnded (Result ProcessError Process.Completed)


init : Env -> ( ModelWrapper, Cmd Msg )
init env =
    case requireCapabilities env of
        Err msg ->
            ( Done
            , Cmd.batch
                [ Cli.println env.stderr (env.programName ++ ": " ++ msg)
                , Cli.exit 1
                ]
            )

        Ok { fs, os } ->
            case OptionsParser.parse env of
                OptionsParser.ParseError formatOptions problem ->
                    ( Done
                    , exitWithProblem env formatOptions problem
                    )

                OptionsParser.ShowHelp options ->
                    ( Done
                    , Cmd.batch
                        [ Cli.println env.stdout (Help.show options)
                        , Cli.exit 0
                        ]
                    )

                OptionsParser.ShowVersion ->
                    ( Done
                    , Cmd.batch
                        [ Cli.println env.stdout CliVersion.version
                        , Cli.exit 0
                        ]
                    )

                OptionsParser.ParseSuccess options ->
                    ( Running
                        { env = env
                        , fs = fs
                        , os = os
                        , options = options
                        }
                    , runReviewProcess os options.appBinary
                    )


requireCapabilities : Env -> Result String { fs : FileSystem, os : ProcessCapability }
requireCapabilities env =
    case Fs.require env of
        Err msg ->
            Err (env.programName ++ ": " ++ msg)

        Ok fs ->
            case Os.requireProcess env of
                Err msg ->
                    Err (env.programName ++ ": " ++ msg)

                Ok os ->
                    Ok { fs = fs, os = os }


updateWrapper : Msg -> ModelWrapper -> ( ModelWrapper, Cmd Msg )
updateWrapper msg wrapper =
    case wrapper of
        Done ->
            ( wrapper, Cmd.none )

        Running model ->
            update msg model
                |> Tuple.mapFirst Running


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        BuildMsg buildMsg ->
            case Build.update buildMsg of
                Ok () ->
                    ( model, Cmd.none )

                Err problem ->
                    ( model
                    , exitWithProblem model.env model.options problem
                    )

        ReviewProcessEnded result ->
            case result of
                Ok completed ->
                    ( model
                    , Cli.exit completed.exitCode
                    )

                Err err ->
                    ( model
                    , Cmd.batch
                        [ Cli.println model.env.stdout ("error: " ++ processErrorToString err)
                        , Cli.exit 1
                        ]
                    )


runReviewProcess : ProcessCapability -> String -> Cmd Msg
runReviewProcess os appBinary =
    Process.run os
        appBinary
        { defaultSpawnOptions
            | args = []
            , stdout = Process.InheritStdout
            , stderr = Process.InheritStderr
        }
        |> Task.attempt ReviewProcessEnded


exitWithProblem : Env -> Problem.FormatOptions options -> Problem.Problem -> Cmd msg
exitWithProblem env formatOptions problem =
    Cmd.batch
        [ Cli.println env.stderr (Problem.format formatOptions problem)
        , Cli.exit 1
        ]


processErrorToString : ProcessError -> String
processErrorToString err =
    case err of
        Process.PermissionDenied ->
            "PermissionDenied"

        Process.CaptureLimitExceeded stream ->
            "CaptureLimitExceeded(" ++ stream ++ ")"

        Process.ProcessError message ->
            message

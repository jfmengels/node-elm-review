module WrapperMain exposing (main)

import Cli exposing (Env)
import Fs exposing (FileSystem)
import Os exposing (ProcessCapability)
import Os.Process as Process exposing (ProcessError, defaultSpawnOptions)
import Task
import Wrapper.Help as Help
import Wrapper.Options
import Wrapper.Options.Parser as OptionsParser


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
    }


type Msg
    = ReviewProcessEnded (Result ProcessError Process.Completed)


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
                OptionsParser.ParseError error ->
                    ( Done
                    , Cmd.batch
                        [ -- TODO Make pretty error message
                          Cli.println env.stderr (error.title ++ ": " ++ error.message)
                        , Cli.exit 1
                        ]
                    )

                OptionsParser.ShowHelp c subcommand ->
                    ( Done
                    , Cmd.batch
                        [ -- TODO Make pretty help
                          Cli.println env.stdout (Help.show c subcommand)
                        , Cli.exit 0
                        ]
                    )

                OptionsParser.ParseSuccess flags ->
                    ( Running { env = env, fs = fs }
                    , Process.run os
                        flags.appBinary
                        { defaultSpawnOptions
                            | args = []
                            , stdout = Process.InheritStdout
                            , stderr = Process.InheritStderr
                        }
                        |> Task.attempt ReviewProcessEnded
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
update (ReviewProcessEnded result) model =
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


processErrorToString : ProcessError -> String
processErrorToString err =
    case err of
        Process.PermissionDenied ->
            "PermissionDenied"

        Process.CaptureLimitExceeded stream ->
            "CaptureLimitExceeded(" ++ stream ++ ")"

        Process.ProcessError message ->
            message

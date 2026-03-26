module WrapperMain exposing (main)

import Cli exposing (Env)
import Fs exposing (FileSystem)
import Wrapper.Flags as Flags


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
    = Noop


init : Env -> ( ModelWrapper, Cmd Msg )
init env =
    case Fs.require env of
        Err msg ->
            ( Done
            , Cmd.batch
                [ Cli.println env.stderr (env.programName ++ ": " ++ msg)
                , Cli.exit 1
                ]
            )

        Ok fs ->
            case Flags.parse env of
                Err error ->
                    ( Done
                    , Cmd.batch
                        [ Cli.println env.stderr error
                        , Cli.exit 1
                        ]
                    )

                Ok flags ->
                    ( Running { env = env, fs = fs }
                    , Cmd.batch
                        [ Cli.println env.stdout ("Got app binary " ++ flags.appBinary)
                        , Cli.exit 0
                        ]
                    )


updateWrapper : Msg -> ModelWrapper -> ( ModelWrapper, Cmd Msg )
updateWrapper msg wrapper =
    case wrapper of
        Done ->
            ( wrapper, Cmd.none )

        Running model ->
            update msg model
                |> Tuple.mapFirst Running


update : Msg -> Model -> ( Model, Cmd Msg )
update Noop model =
    ( model, Cmd.none )

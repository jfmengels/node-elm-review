module Elm.Review.ElmRunProgram exposing (Config, Program, program)

import Capabilities exposing (Console, Stdin)
import Cli as ElmRunCli exposing (Env)
import Dict exposing (Dict)
import Elm.Review.ElmRunEffects as ElmRunEffects
import Elm.Review.InitError as InitError
import Elm.Review.Testable as Testable exposing (Effects)
import Elm.Review.Testable.Internal exposing (TCmd)
import ElmReview.Color as Color
import ElmReview.Problem as Problem exposing (Problem)
import ElmReview.ReportMode as ReportMode
import Fs as ElmRunFs exposing (FileSystem, FsError(..))
import Os exposing (ProcessCapability)


type ModelWrapper model
    = Done
    | Running (Model model)


type alias Model model =
    { fs : FileSystem
    , os : ProcessCapability
    , stdin : Maybe Stdin
    , stdout : Console
    , stderr : Console
    , mainModel : model
    }


type alias Config model msg =
    { init : Flags -> InitError.InitError ( model, TCmd msg )
    , update : msg -> model -> ( model, TCmd msg )
    , subscriptions : model -> Sub msg
    }


type alias Flags =
    { args : List String
    , env : Dict String String
    , stdin : Maybe Stdin
    }


type alias Program model msg =
    ElmRunCli.Program (ModelWrapper model) msg


program : Config model msg -> Program model msg
program config =
    ElmRunCli.program
        { init = init config.init
        , update = update config.update
        , subscriptions = subscriptions config.subscriptions
        }


init : (Flags -> InitError.InitError ( model, TCmd msg )) -> Env -> ( ModelWrapper model, Cmd msg )
init initFn env =
    case requireCapabilities env of
        Ok { fs, os } ->
            case initFn { args = env.args, env = env.env, stdin = env.stdin } of
                InitError.Success ( mainModel, cmd ) ->
                    ( Running
                        { fs = fs
                        , os = os
                        , stdin = env.stdin
                        , stdout = env.stdout
                        , stderr = env.stderr
                        , mainModel = mainModel
                        }
                    , Testable.cmd (ElmRunEffects.effects fs os env.stdin env.stdout env.stderr) cmd
                    )

                InitError.Problem formatOptions problem ->
                    ( Done
                    , stop env.stderr formatOptions problem
                    )

                InitError.StringProblem string ->
                    ( Done
                    , Cmd.batch
                        [ ElmRunCli.println env.stdout string
                        , ElmRunCli.exit 1
                        ]
                    )

        Err problem ->
            ( Done
            , stop env.stderr (roughFormatOptions env.args) problem
            )


update : (msg -> model -> ( model, TCmd msg )) -> msg -> ModelWrapper model -> ( ModelWrapper model, Cmd msg )
update updateFn msg modelWrapper =
    case modelWrapper of
        Done ->
            ( Done, Cmd.none )

        Running { fs, os, stdin, stdout, stderr, mainModel } ->
            let
                ( newMainModel, cmd ) =
                    updateFn msg mainModel
            in
            ( Running
                { fs = fs
                , os = os
                , stdin = stdin
                , stdout = stdout
                , stderr = stderr
                , mainModel = newMainModel
                }
            , Testable.cmd (ElmRunEffects.effects fs os stdin stdout stderr) cmd
            )


subscriptions : (model -> Sub msg) -> ModelWrapper model -> Sub msg
subscriptions subsFn model =
    case model of
        Done ->
            Sub.none

        Running { mainModel } ->
            subsFn mainModel


stop : Console -> Problem.FormatOptions options -> Problem -> Cmd msg
stop stderr formatOptions problem =
    Cmd.batch
        [ ElmRunCli.println stderr (Problem.format formatOptions problem)
        , ElmRunCli.exit 1
        ]


roughFormatOptions : List String -> Problem.FormatOptions { attemptFutureRecovery : Bool }
roughFormatOptions args =
    { color = Color.noColors
    , reportMode =
        if List.member "--report=json" args || List.member "--report=ndjson" args then
            ReportMode.Json

        else
            ReportMode.HumanReadable
    , debug = List.member "--debug" args
    , attemptFutureRecovery = False
    }


requireCapabilities : Env -> Result Problem { fs : FileSystem, os : ProcessCapability }
requireCapabilities env =
    Result.map2 (\fs os -> { fs = fs, os = os })
        (ElmRunFs.require env)
        (Os.requireProcess env)
        |> Result.mapError
            (\err ->
                Problem.from Problem.Unrecoverable
                    { title = "MISSING CAPABILITIES"
                    , message = \_ -> "elm-review was run with missing capabilities:\n\n    " ++ err
                    }
            )

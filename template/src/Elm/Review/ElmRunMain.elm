module Elm.Review.ElmRunMain exposing (main)

import Capabilities exposing (Console, Stdin)
import Cli as ElmRunCli exposing (Env)
import Elm.Review.ElmRunEffects as ElmRunEffects
import Elm.Review.Main as Main
import Elm.Review.Options as Options
import Elm.Review.Testable as Testable exposing (Effects)
import ElmReview.Color as Color
import ElmReview.Problem as Problem exposing (Problem)
import ElmReview.ReportMode as ReportMode
import Fs as ElmRunFs exposing (FileSystem, FsError(..))
import Os exposing (ProcessCapability)


type ModelWrapper
    = Done
    | Running Model


type alias Model =
    { fs : FileSystem
    , os : ProcessCapability
    , stdout : Console
    , stderr : Console
    , mainModel : Main.Model
    }


main : ElmRunCli.Program ModelWrapper Main.Msg
main =
    ElmRunCli.program
        { init = init
        , update = update
        , subscriptions = subscriptions
        }


init : Env -> ( ModelWrapper, Cmd Main.Msg )
init env =
    case Result.map2 Tuple.pair (requireCapabilities env) (Options.parse env.args) of
        Ok ( { fs, os }, options ) ->
            case Main.init env.stdin options of
                Ok ( mainModel, cmd ) ->
                    ( Running
                        { fs = fs
                        , os = os
                        , stdout = env.stdout
                        , stderr = env.stderr
                        , mainModel = mainModel
                        }
                    , Testable.cmd (ElmRunEffects.effects fs os env.stdout env.stderr) cmd
                    )

                Err cmd ->
                    ( Done
                    , Testable.cmd (ElmRunEffects.effects fs os env.stdout env.stderr) cmd
                    )

        Err err ->
            ( Done
            , stop env.stderr (roughFormatOptions env.args) err
            )


update : Main.Msg -> ModelWrapper -> ( ModelWrapper, Cmd Main.Msg )
update msg modelWrapper =
    case modelWrapper of
        Done ->
            ( Done, Cmd.none )

        Running { fs, os, stdout, stderr, mainModel } ->
            let
                ( newMainModel, cmd ) =
                    Main.update msg mainModel
            in
            ( Running
                { fs = fs
                , os = os
                , stdout = stdout
                , stderr = stderr
                , mainModel = newMainModel
                }
            , Testable.cmd (ElmRunEffects.effects fs os stdout stderr) cmd
            )


subscriptions : ModelWrapper -> Sub Main.Msg
subscriptions model =
    case model of
        Done ->
            Sub.none

        Running { mainModel } ->
            Main.subscriptions mainModel


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

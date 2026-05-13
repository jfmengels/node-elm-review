module Elm.Review.NodeProgram exposing (Config, Program, program)

import Dict exposing (Dict)
import Elm.Review.InitError as InitError
import Elm.Review.NodeEffects as NodeEffects
import Elm.Review.Testable as Testable exposing (Effects)
import Elm.Review.Testable.Internal exposing (TCmd)
import Elm.Review.Testable.TSub as TSub exposing (TSub)
import ElmReview.Problem as Problem exposing (Problem)
import Json.Decode as Decode


type ModelWrapper model
    = Done
    | Running (Model model)


type alias Model model =
    { mainModel : model
    }


type alias Config model msg =
    { init : Flags -> InitError.InitError ( model, TCmd msg )
    , update : msg -> model -> ( model, TCmd msg )
    , subscriptions : model -> TSub msg
    }


type alias Flags =
    { args : List String
    , env : Dict String String
    }


type alias Program model msg =
    Platform.Program Decode.Value (ModelWrapper model) msg


program : Config model msg -> Program model msg
program config =
    Platform.worker
        { init = init config.init
        , update = update config.update
        , subscriptions = subscriptions config.subscriptions
        }


init : (Flags -> InitError.InitError ( model, TCmd msg )) -> Decode.Value -> ( ModelWrapper model, Cmd msg )
init initFn rawFlags =
    case Decode.decodeValue flagsDecoder rawFlags of
        Ok flags ->
            case initFn flags of
                InitError.Success ( mainModel, cmd ) ->
                    ( Running
                        { mainModel = mainModel
                        }
                    , Testable.cmd NodeEffects.effects cmd
                    )

                InitError.Problem formatOptions problem ->
                    ( Done
                    , stop formatOptions problem
                    )

                InitError.StringProblem string ->
                    ( Done
                    , Debug.todo "stop on stringProblem"
                    )

        Err decodingError ->
            ( Done
            , Debug.todo ("Problem decoding flags: " ++ Decode.errorToString decodingError)
            )


flagsDecoder : Decode.Decoder Flags
flagsDecoder =
    Decode.map2 Flags
        (Decode.field "args" (Decode.list Decode.string))
        (Decode.field "env" (Decode.dict Decode.string))


update : (msg -> model -> ( model, TCmd msg )) -> msg -> ModelWrapper model -> ( ModelWrapper model, Cmd msg )
update updateFn msg modelWrapper =
    case modelWrapper of
        Done ->
            ( Done, Cmd.none )

        Running { mainModel } ->
            let
                ( newMainModel, cmd ) =
                    updateFn msg mainModel
            in
            ( Running
                { mainModel = newMainModel
                }
            , Testable.cmd NodeEffects.effects cmd
            )


subscriptions : (model -> TSub msg) -> ModelWrapper model -> Sub msg
subscriptions subsFn model =
    case model of
        Done ->
            Sub.none

        Running { mainModel } ->
            TSub.subscriptions NodeEffects.subEffects (subsFn mainModel)


stop : Problem.FormatOptions options -> Problem -> Cmd msg
stop formatOptions problem =
    Debug.todo "stop"

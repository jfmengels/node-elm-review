port module LintApp exposing (main)

import File exposing (File)
import Json.Decode as Decode
import Json.Encode as Encode
import Lint exposing (LintError, Severity(..), lintSource)
import Lint.Rule exposing (Rule)
import LintConfig exposing (config)
import Reporter.CliReporter


port collectFile : (Decode.Value -> msg) -> Sub msg


port acknowledgeFileReceipt : String -> Cmd msg


port requestToLint : (Bool -> msg) -> Sub msg


port resultPort : { success : Bool, report : Encode.Value } -> Cmd msg



-- PROGRAM


type alias Flags =
    ()


main : Program Flags Model Msg
main =
    Platform.worker
        { init = init
        , update = update
        , subscriptions = subscriptions
        }



-- MODEL


type alias Model =
    { files : List File
    }


init : Flags -> ( Model, Cmd msg )
init () =
    ( { files = [] }, Cmd.none )



-- UPDATE


type Msg
    = ReceivedFile Decode.Value
    | GotRequestToLint


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ReceivedFile rawFile ->
            case Decode.decodeValue File.decode rawFile of
                Ok file ->
                    ( { model | files = file :: model.files }
                    , acknowledgeFileReceipt <| File.name file
                    )

                Err err ->
                    let
                        _ =
                            Debug.log "file decoding" err
                    in
                    ( model, Cmd.none )

        GotRequestToLint ->
            let
                errors : List ( File, List ( Severity, LintError ) )
                errors =
                    model.files
                        |> List.map (\file -> ( file, lint file ))
                        |> List.filter
                            (Tuple.second >> List.isEmpty >> not)

                success : Bool
                success =
                    errors
                        |> List.concatMap Tuple.second
                        |> List.filter (Tuple.first >> (==) Critical)
                        |> List.length
                        |> (==) 0

                report : Encode.Value
                report =
                    Reporter.CliReporter.formatReport errors
            in
            ( model
            , resultPort { success = success, report = report }
            )



-- LINTING


lint : File -> List ( Severity, LintError )
lint file =
    case lintSource enabledRules <| File.source file of
        Err errors ->
            [ ( Critical
              , { file = Just <| File.name file
                , ruleName = "Parsing error"
                , message = "Could not parse file: " ++ File.name file
                , range = { start = { row = 0, column = 0 }, end = { row = 0, column = 0 } }
                }
              )
            ]

        Ok result ->
            result


enabledRules : List ( Severity, Rule )
enabledRules =
    config
        |> List.filter (Tuple.first >> (/=) Disabled)



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ collectFile ReceivedFile
        , requestToLint (\_ -> GotRequestToLint)
        ]

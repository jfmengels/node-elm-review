port module LintApp exposing (main)

import File exposing (File)
import Json.Decode as Decode
import Lint exposing (LintError, Severity(..), lintSource)
import Lint.Rule exposing (Rule)
import LintConfig exposing (config)
import Reporter.CliReporter


port collectFile : (Decode.Value -> msg) -> Sub msg


port finishedCollecting : (Bool -> msg) -> Sub msg


port resultPort : { success : Bool, report : String } -> Cmd msg


type alias Model =
    { files : List File
    }


type Msg
    = CollectFile Decode.Value
    | FinishedCollecting


enabledRules : List ( Severity, Rule )
enabledRules =
    config
        |> List.filter (Tuple.first >> (/=) Disabled)


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


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        CollectFile rawFile ->
            case Decode.decodeValue File.decode rawFile of
                Ok file ->
                    ( { model | files = file :: model.files }, Cmd.none )

                Err err ->
                    let
                        _ =
                            Debug.log "file decoding" err
                    in
                    ( model, Cmd.none )

        FinishedCollecting ->
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

                report : String
                report =
                    Reporter.CliReporter.formatReport errors
            in
            ( model
            , resultPort { success = success, report = report }
            )


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ collectFile CollectFile
        , finishedCollecting (\_ -> FinishedCollecting)
        ]


main : Program () Model Msg
main =
    Platform.worker
        { init = \() -> ( { files = [] }, Cmd.none )
        , update = update
        , subscriptions = subscriptions
        }

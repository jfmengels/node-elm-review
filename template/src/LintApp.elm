port module LintApp exposing (main)

import File exposing (File)
import Json.Decode as Decode
import Json.Encode as Encode
import Lint exposing (LintError, lintSource)
import LintConfig exposing (config)
import Reporter
import Text



-- PORTS


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
                    , acknowledgeFileReceipt file.name
                    )

                Err err ->
                    ( model, Cmd.none )

        GotRequestToLint ->
            let
                errors : List ( File, List LintError )
                errors =
                    model.files
                        |> List.map (\file -> ( file, lint file ))
                        |> List.filter (Tuple.second >> List.isEmpty >> not)

                success : Bool
                success =
                    errors
                        |> List.concatMap Tuple.second
                        |> List.length
                        |> (==) 0

                report : Encode.Value
                report =
                    Reporter.formatReport errors
                        |> Text.encode
            in
            ( model
            , resultPort { success = success, report = report }
            )



-- LINTING


lint : File -> List LintError
lint file =
    lintSource
        config
        { fileName = file.name, source = file.source }


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ collectFile ReceivedFile
        , requestToLint (\_ -> GotRequestToLint)
        ]

port module LintApp exposing (main)

import File exposing (File)
import Json.Decode as Decode
import Json.Encode as Encode
import Lint exposing (LintError, lintSource)
import Lint.Rule exposing (Rule)
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
                errors : List ( File, List LintError )
                errors =
                    model.files
                        |> List.map (\file -> ( file, lint file ))
                        |> List.filter
                            (Tuple.second >> List.isEmpty >> not)

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
    case lintSource config <| File.source file of
        Err errors ->
            [ { file = Just <| File.name file
              , ruleName = "Parsing error"
              , message = "Could not parse file: " ++ File.name file
              , details =
                    [ "I could not understand the contents of this file, and this prevents me from analyzing it. It's highly likely that the contents of the file is not valid Elm code."
                    , "Hint: Try running `elm make`. The compiler should give you better hints on how to resolve the problem."
                    ]
              , range = { start = { row = 0, column = 0 }, end = { row = 0, column = 0 } }
              }
            ]

        Ok result ->
            result



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ collectFile ReceivedFile
        , requestToLint (\_ -> GotRequestToLint)
        ]

port module LintApp exposing (main)

import File exposing (File)
import Json.Decode as Decode
import Json.Encode as Encode
import Lint exposing (LintError, lintSource)
import LintConfig exposing (config)
import Reporter



-- PORTS


port collectFile : (Decode.Value -> msg) -> Sub msg


port acknowledgeFileReceipt : String -> Cmd msg


port requestToLint : (Bool -> msg) -> Sub msg


port resultPort : { success : Bool, report : Encode.Value, fixedFiles : Encode.Value } -> Cmd msg



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
                    , acknowledgeFileReceipt file.path
                    )

                Err err ->
                    ( model, Cmd.none )

        GotRequestToLint ->
            let
                errors : List ( File, List LintError )
                errors =
                    model.files
                        |> List.map (\file -> ( file, lint file ))

                success : Bool
                success =
                    errors
                        |> List.concatMap Tuple.second
                        |> List.length
                        |> (==) 0

                report : Encode.Value
                report =
                    errors
                        |> fromLintErrors
                        |> Reporter.formatReport
                        |> encodeReport

                fixedFiles : List File
                fixedFiles =
                    errors
                        |> List.filterMap
                            (\( file, errorsForFile ) ->
                                findFirstFix errorsForFile
                                    |> Maybe.map (\fixedSource -> { file | source = fixedSource })
                            )
            in
            ( model
            , resultPort
                { success = success
                , report = report
                , fixedFiles = Encode.list File.encode fixedFiles
                }
            )


findFirstFix : List LintError -> Maybe String
findFirstFix errors =
    case errors of
        [] ->
            Nothing

        error :: restOfErrors ->
            case applyFixFromError error of
                Just fix ->
                    Just fix

                Nothing ->
                    findFirstFix restOfErrors


applyFixFromError : LintError -> Maybe String
applyFixFromError error =
    Lint.fixedSource error
        |> Maybe.map (\fixSource -> fixSource ())


fromLintErrors : List ( File, List LintError ) -> List ( File, List Reporter.Error )
fromLintErrors errors =
    (List.map <| Tuple.mapSecond <| List.map fromLintError) errors


fromLintError : LintError -> Reporter.Error
fromLintError error =
    { moduleName = Lint.errorModuleName error
    , ruleName = Lint.errorRuleName error
    , message = Lint.errorMessage error
    , details = Lint.errorDetails error
    , range = Lint.errorRange error
    , fixedSource = Lint.fixedSource error
    }



-- ENCODING


{-| Encode texts to a JSON value.
-}
encodeReport : List { str : String, color : Maybe ( Int, Int, Int ) } -> Encode.Value
encodeReport texts =
    texts
        |> Encode.list encodeReportPart


encodeReportPart : { str : String, color : Maybe ( Int, Int, Int ) } -> Encode.Value
encodeReportPart { str, color } =
    Encode.object
        [ ( "string", Encode.string str )
        , ( "color"
          , case color of
                Just ( red, green, blue ) ->
                    Encode.list Encode.int [ red, green, blue ]

                Nothing ->
                    Encode.null
          )
        ]



-- LINTING


lint : File -> List LintError
lint file =
    lintSource config file


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ collectFile ReceivedFile
        , requestToLint (\_ -> GotRequestToLint)
        ]

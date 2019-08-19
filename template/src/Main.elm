port module Main exposing (main)

import File exposing (File)
import Json.Decode as Decode
import Json.Encode as Encode
import Lint exposing (LintError, lintSource)
import Lint.Fix as Fix
import LintConfig exposing (config)
import Reporter



-- PORTS


port collectFile : (Decode.Value -> msg) -> Sub msg


port acknowledgeFileReceipt : String -> Cmd msg


port requestToLint : (Bool -> msg) -> Sub msg


port resultPort : { success : Bool, report : Encode.Value, fixedFiles : Encode.Value } -> Cmd msg


port abort : String -> Cmd msg



-- PROGRAM


type alias Flags =
    Encode.Value


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
    , fixMode : FixMode
    }


type FixMode
    = DontFix
    | FixOneByOne
    | FixAll


init : Flags -> ( Model, Cmd msg )
init flags =
    case Decode.decodeValue decodeFlags flags of
        Ok fixMode ->
            ( { files = [], fixMode = fixMode }, Cmd.none )

        Err _ ->
            ( { files = [], fixMode = DontFix }
            , abort <| "Problem decoding the flags when running the elm-lint runner"
            )


decodeFlags : Decode.Decoder FixMode
decodeFlags =
    Decode.field "fixMode" Decode.string
        |> Decode.andThen
            (\fixMode ->
                case fixMode of
                    "dontfix" ->
                        Decode.succeed DontFix

                    "fix-one-by-one" ->
                        Decode.succeed FixOneByOne

                    "fix-all" ->
                        Decode.succeed FixAll

                    _ ->
                        Decode.fail <| "I could not understand the following fix mode: " ++ fixMode
            )



-- UPDATE


type Msg
    = ReceivedFile Decode.Value
    | GotRequestToLint


type alias Source =
    String


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
            runLinting model


runLinting : Model -> ( Model, Cmd msg )
runLinting model =
    case model.fixMode of
        DontFix ->
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
                        |> Reporter.formatReport Reporter.Linting
                        |> encodeReport
            in
            ( model
            , resultPort
                { success = success
                , report = report
                , fixedFiles = Encode.list File.encode []
                }
            )

        FixOneByOne ->
            ( model, Cmd.none )

        FixAll ->
            fixAll model


type FileFixResult
    = Unchanged
    | Fixed


fixAll : Model -> ( Model, Cmd msg )
fixAll model =
    let
        errors : List ( ( FileFixResult, File ), List LintError )
        errors =
            model.files
                |> List.map
                    (\file ->
                        let
                            ( newFile, errorsForFile ) =
                                fixAllForOneFile file

                            fileFixResult : FileFixResult
                            fileFixResult =
                                if file == newFile then
                                    Unchanged

                                else
                                    Fixed
                        in
                        ( ( fileFixResult, newFile ), errorsForFile )
                    )

        success : Bool
        success =
            errors
                |> List.concatMap Tuple.second
                |> List.length
                |> (==) 0

        report : Encode.Value
        report =
            errors
                |> List.map (Tuple.mapFirst Tuple.second)
                |> fromLintErrors
                |> Reporter.formatReport Reporter.Fixing
                |> encodeReport

        fixedFiles : List File
        fixedFiles =
            errors
                |> List.filterMap
                    (\( ( fileFixResult, file ), errorsForFile ) ->
                        case fileFixResult of
                            Unchanged ->
                                Nothing

                            Fixed ->
                                Just file
                    )
    in
    ( model
    , resultPort
        { success = success
        , report = report
        , fixedFiles = Encode.list File.encode fixedFiles
        }
    )


fixAllForOneFile : File -> ( File, List LintError )
fixAllForOneFile file =
    let
        errors : List LintError
        errors =
            lint file
    in
    -- Check if there are fixes available for this file
    case findFirstFix file.source errors of
        -- if there are none, return the remaining errors
        Nothing ->
            ( file, errors )

        -- if there is then
        Just fixResult ->
            case fixResult of
                Fix.Successful fixedSource ->
                    -- if the fix makes change successfully, update the file, and
                    -- relint from scratch (ignoring the previously computed errors)
                    fixAllForOneFile { file | source = fixedSource }

                Fix.Errored _ ->
                    -- if the fix could not be applied, ignore it, and stop here
                    ( file, errors )


findFirstFix : Source -> List LintError -> Maybe Fix.Result
findFirstFix source errors =
    case errors of
        [] ->
            Nothing

        error :: restOfErrors ->
            case applyFixFromError source error of
                Just fix ->
                    Just fix

                Nothing ->
                    findFirstFix source restOfErrors


applyFixFromError : Source -> LintError -> Maybe Fix.Result
applyFixFromError source error =
    error
        |> Lint.errorFixes
        |> Maybe.map (\fixes -> Fix.fix fixes source)


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
    , hasFix = Lint.errorFixes error /= Nothing
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

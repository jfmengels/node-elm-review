port module Main exposing (main)

import Dict exposing (Dict)
import Elm.Syntax.Range exposing (Range)
import File exposing (File)
import Json.Decode as Decode
import Json.Encode as Encode
import Lint
import Lint.Fix as Fix
import LintConfig exposing (config)
import Reporter
import Set exposing (Set)



-- PORTS


port collectFile : (Decode.Value -> msg) -> Sub msg


port acknowledgeFileReceipt : String -> Cmd msg


port requestToLint : (Bool -> msg) -> Sub msg


port resultPort : { success : Bool, report : Encode.Value, fixedFiles : Encode.Value } -> Cmd msg


port userConfirmedFix : (Decode.Value -> msg) -> Sub msg


port askConfirmationToFix : { file : Encode.Value, error : String } -> Cmd msg


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
    , lintErrors : Dict File (List Lint.Error)
    , errorsRefused : Set String
    , errorAwaitingConfirmation : Maybe Lint.Error
    }


type FixMode
    = DontFix
    | Fix


init : Flags -> ( Model, Cmd msg )
init flags =
    case Decode.decodeValue decodeFlags flags of
        Ok fixMode ->
            ( { files = []
              , fixMode = fixMode
              , lintErrors = Dict.empty
              , errorAwaitingConfirmation = Nothing
              , errorsRefused = Set.empty
              }
            , Cmd.none
            )

        Err _ ->
            ( { files = []
              , fixMode = DontFix
              , lintErrors = Dict.empty
              , errorAwaitingConfirmation = Nothing
              , errorsRefused = Set.empty
              }
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

                    "fix" ->
                        Decode.succeed Fix

                    _ ->
                        Decode.fail <| "I could not understand the following fix mode: " ++ fixMode
            )



-- UPDATE


type Msg
    = ReceivedFile Decode.Value
    | GotRequestToLint
    | UserConfirmedFix Decode.Value


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

        UserConfirmedFix confirmation ->
            case Decode.decodeValue confirmationDecoder confirmation of
                Ok (Accepted updatedFile) ->
                    { model
                        | errorAwaitingConfirmation = Nothing
                        , files =
                            List.map
                                (\file ->
                                    if file.path == updatedFile.path then
                                        updatedFile

                                    else
                                        file
                                )
                                model.files
                    }
                        |> runLinting

                Ok Refused ->
                    case model.errorAwaitingConfirmation of
                        Just errorAwaitingConfirmation ->
                            model
                                |> refuseError errorAwaitingConfirmation
                                |> runLinting

                        Nothing ->
                            runLinting model

                Err err ->
                    ( model, abort <| Decode.errorToString err )


refuseError : Lint.Error -> Model -> Model
refuseError error model =
    { model | errorsRefused = Set.insert (errorKey error) model.errorsRefused }


errorKey : Lint.Error -> String
errorKey error =
    let
        range : Range
        range =
            Lint.errorRange error
    in
    String.join "###"
        [ Lint.errorRuleName error
        , Lint.errorModuleName error |> Maybe.withDefault "unknown module name"
        , Lint.errorMessage error
        , Lint.errorDetails error |> String.join "\n"
        , [ range.start.row
          , range.start.column
          , range.end.row
          , range.end.column
          ]
            |> List.map String.fromInt
            |> String.join "-"
        ]


type Confirmation
    = Accepted File
    | Refused


confirmationDecoder : Decode.Decoder Confirmation
confirmationDecoder =
    Decode.field "answer" Decode.bool
        |> Decode.andThen
            (\accepted ->
                if accepted then
                    Decode.field "file" File.decode
                        |> Decode.map Accepted

                else
                    Decode.succeed Refused
            )


runLinting : Model -> ( Model, Cmd msg )
runLinting model =
    case model.fixMode of
        DontFix ->
            let
                errors : List ( File, List Lint.Error )
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

        Fix ->
            fixOneByOne model


fixOneByOne : Model -> ( Model, Cmd msg )
fixOneByOne model =
    let
        lintErrors : List ( File, List Lint.Error )
        lintErrors =
            model.files
                |> List.map (\file -> ( file, lint file ))
    in
    case findFix model.errorsRefused lintErrors of
        Just ( file, error, fixedSource ) ->
            ( { model | errorAwaitingConfirmation = Just error }
            , askConfirmationToFix
                { file = File.encode { file | source = fixedSource }
                , error = Lint.errorMessage error
                }
            )

        Nothing ->
            ( model
            , Cmd.none
              -- , resultPort
              --     { success = success
              --     , report = report
              --     , fixedFiles = Encode.list File.encode fixedFiles
              --     }
            )


findFix : Set String -> List ( File, List Lint.Error ) -> Maybe ( File, Lint.Error, String )
findFix errorsRefused errors =
    case errors of
        [] ->
            Nothing

        ( file, errorsForFile ) :: restOfErrors ->
            case findFixForFile errorsRefused file.source errorsForFile of
                Just ( error, fixedSource ) ->
                    Just ( file, error, fixedSource )

                Nothing ->
                    findFix errorsRefused restOfErrors


findFixForFile : Set String -> String -> List Lint.Error -> Maybe ( Lint.Error, String )
findFixForFile errorsRefused source errors =
    case errors of
        [] ->
            Nothing

        error :: restOfErrors ->
            if Set.member (errorKey error) errorsRefused then
                findFixForFile errorsRefused source restOfErrors

            else
                case applyFixFromError source error of
                    Just (Fix.Successful fixedSource) ->
                        Just ( error, fixedSource )

                    Just (Fix.Errored _) ->
                        findFixForFile errorsRefused source restOfErrors

                    Nothing ->
                        findFixForFile errorsRefused source restOfErrors


fixAllForOneFile : File -> ( File, List Lint.Error )
fixAllForOneFile file =
    let
        errors : List Lint.Error
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


findFirstFix : Source -> List Lint.Error -> Maybe Fix.Result
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


applyFixFromError : Source -> Lint.Error -> Maybe Fix.Result
applyFixFromError source error =
    error
        |> Lint.errorFixes
        |> Maybe.map (\fixes -> Fix.fix fixes source)


fromLintErrors : List ( File, List Lint.Error ) -> List ( File, List Reporter.Error )
fromLintErrors errors =
    (List.map <| Tuple.mapSecond <| List.map fromLintError) errors


fromLintError : Lint.Error -> Reporter.Error
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


lint : File -> List Lint.Error
lint file =
    Lint.lint config file


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ collectFile ReceivedFile
        , requestToLint (\_ -> GotRequestToLint)
        , userConfirmedFix UserConfirmedFix
        ]

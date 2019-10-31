port module Elm.Review.Main exposing (main)

import Dict exposing (Dict)
import Elm.Project
import Elm.Review.File as File
import Elm.Review.RefusedErrorFixes as RefusedErrorFixes exposing (RefusedErrorFixes)
import Json.Decode as Decode
import Json.Encode as Encode
import Reporter
import Review
import Review.File exposing (ParsedFile, RawFile)
import Review.Fix as Fix exposing (FixResult)
import Review.Project
import ReviewConfig exposing (config)



-- PORTS


port collectFile : (Decode.Value -> msg) -> Sub msg


port collectElmJson : (Decode.Value -> msg) -> Sub msg


port acknowledgeFileReceipt : String -> Cmd msg


port startReview : (Bool -> msg) -> Sub msg


port reviewReport : { success : Bool, report : Encode.Value } -> Cmd msg


port userConfirmedFix : (Decode.Value -> msg) -> Sub msg


port askConfirmationToFix : { file : Encode.Value, error : String, confirmationMessage : Encode.Value } -> Cmd msg


port abort : String -> Cmd msg



-- PROGRAM


type alias Flags =
    Encode.Value


main : Program Flags Model Msg
main =
    Platform.worker
        { init = init
        , update = update
        , subscriptions = \_ -> subscriptions
        }



-- MODEL


type alias Model =
    { files : Dict String ParsedFile
    , project : Review.Project.Project
    , fixMode : FixMode
    , reviewErrors : List Review.Error
    , parseErrors : List ( RawFile, List Reporter.Error )
    , refusedErrorFixes : RefusedErrorFixes
    , errorAwaitingConfirmation : Maybe Review.Error
    }


type FixMode
    = DontFix
    | Fix


init : Flags -> ( Model, Cmd msg )
init flags =
    case Decode.decodeValue decodeFlags flags of
        Ok fixMode ->
            ( { files = Dict.empty
              , project = Review.Project.new
              , fixMode = fixMode
              , reviewErrors = []
              , parseErrors = []
              , errorAwaitingConfirmation = Nothing
              , refusedErrorFixes = RefusedErrorFixes.empty
              }
            , Cmd.none
            )

        Err _ ->
            ( { files = Dict.empty
              , project = Review.Project.new
              , fixMode = DontFix
              , reviewErrors = []
              , parseErrors = []
              , errorAwaitingConfirmation = Nothing
              , refusedErrorFixes = RefusedErrorFixes.empty
              }
            , abort <| "Problem decoding the flags when running the elm-review runner"
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
    | ReceivedElmJson Decode.Value
    | GotRequestToReview
    | UserConfirmedFix Decode.Value


type alias Source =
    String


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ReceivedFile json ->
            case Decode.decodeValue File.decode json of
                Ok rawFile ->
                    case Review.parseFile rawFile of
                        Ok parsedFile ->
                            ( { model | files = Dict.insert parsedFile.path parsedFile model.files }
                            , acknowledgeFileReceipt parsedFile.path
                            )

                        Err parseError ->
                            ( { model | parseErrors = ( rawFile, [ fromReviewError parseError ] ) :: model.parseErrors }
                            , acknowledgeFileReceipt rawFile.path
                            )

                Err err ->
                    ( model, Cmd.none )

        ReceivedElmJson rawElmJson ->
            case Decode.decodeValue Elm.Project.decoder rawElmJson of
                Ok elmJson ->
                    ( { model | project = Review.Project.withElmJson elmJson model.project }
                    , Cmd.none
                    )

                Err err ->
                    ( model, Cmd.none )

        GotRequestToReview ->
            runReview model

        UserConfirmedFix confirmation ->
            case Decode.decodeValue confirmationDecoder confirmation of
                Ok (Accepted rawFile) ->
                    case Review.parseFile rawFile of
                        Ok parsedFile ->
                            { model
                                | errorAwaitingConfirmation = Nothing
                                , files = Dict.insert parsedFile.path parsedFile model.files
                            }
                                |> reReviewFile parsedFile
                                |> fixOneByOne

                        Err _ ->
                            ( model
                              -- TODO Improve abort message
                            , abort <| "File " ++ rawFile.path ++ " could not be read. An incorrect fix may have been introduced into this file..."
                            )

                Ok Refused ->
                    case model.errorAwaitingConfirmation of
                        Just errorAwaitingConfirmation ->
                            model
                                |> refuseError errorAwaitingConfirmation
                                |> fixOneByOne

                        Nothing ->
                            fixOneByOne model

                Err err ->
                    ( model, abort <| Decode.errorToString err )


reReviewFile : ParsedFile -> Model -> Model
reReviewFile updatedFile model =
    -- { model | reviewErrors = replaceFileErrors updatedFile (review model.project updatedFile) model.reviewErrors }
    Debug.todo "reReviewFile"


replaceFileErrors : ParsedFile -> List Review.Error -> List ( ParsedFile, List Review.Error ) -> List ( ParsedFile, List Review.Error )
replaceFileErrors updatedFile errorsForFile allErrors =
    case allErrors of
        [] ->
            []

        (( file, _ ) as fileAndErrors) :: restOfErrors ->
            if file.path == updatedFile.path then
                ( updatedFile, errorsForFile ) :: restOfErrors

            else
                fileAndErrors :: replaceFileErrors updatedFile errorsForFile restOfErrors


refuseError : Review.Error -> Model -> Model
refuseError error model =
    { model | refusedErrorFixes = RefusedErrorFixes.insert error model.refusedErrorFixes }


type Confirmation
    = Accepted RawFile
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


runReview : Model -> ( Model, Cmd msg )
runReview model =
    let
        modelWithErrors : Model
        modelWithErrors =
            { model | reviewErrors = Review.reviewFiles config model.project (Dict.values model.files) }
    in
    case modelWithErrors.fixMode of
        DontFix ->
            makeReport modelWithErrors

        Fix ->
            fixOneByOne modelWithErrors


makeReport : Model -> ( Model, Cmd msg )
makeReport model =
    let
        errors : List ( RawFile, List Reporter.Error )
        errors =
            List.concat
                [ fromReviewErrors model.files model.reviewErrors
                , model.parseErrors
                ]

        success : Bool
        success =
            errors
                |> List.length
                |> (==) 0

        report : Encode.Value
        report =
            errors
                |> Reporter.formatReport Reporter.Reviewing
                |> encodeReport
    in
    ( model
    , reviewReport
        { success = success
        , report = report
        }
    )


fixOneByOne : Model -> ( Model, Cmd msg )
fixOneByOne model =
    -- case findFix model.refusedErrorFixes model.reviewErrors of
    --     Just ( file, error, fixedSource ) ->
    --         ( { model | errorAwaitingConfirmation = Just error }
    --         , askConfirmationToFix
    --             { file = File.encode { file | source = fixedSource }
    --             , error = Review.errorMessage error
    --             , confirmationMessage =
    --                 Reporter.formatFixProposal file (fromReviewError error) fixedSource
    --                     |> encodeReport
    --             }
    --         )
    --
    --     Nothing ->
    --         makeReport model
    Debug.todo "fixOneByOne"


findFix : RefusedErrorFixes -> List ( ParsedFile, List Review.Error ) -> Maybe ( ParsedFile, Review.Error, String )
findFix refusedErrorFixes errors =
    case errors of
        [] ->
            Nothing

        ( file, errorsForFile ) :: restOfErrors ->
            case findFixForFile refusedErrorFixes file.source errorsForFile of
                Just ( error, fixedSource ) ->
                    Just ( file, error, fixedSource )

                Nothing ->
                    findFix refusedErrorFixes restOfErrors


findFixForFile : RefusedErrorFixes -> String -> List Review.Error -> Maybe ( Review.Error, String )
findFixForFile refusedErrorFixes source errors =
    case errors of
        [] ->
            Nothing

        error :: restOfErrors ->
            if RefusedErrorFixes.member error refusedErrorFixes then
                -- Ignore error if it was previously refused by the user
                findFixForFile refusedErrorFixes source restOfErrors

            else
                case applyFixFromError source error of
                    Nothing ->
                        -- Ignore error if it has no fixes
                        findFixForFile refusedErrorFixes source restOfErrors

                    Just (Fix.Errored _) ->
                        -- Ignore error if applying the fix results in a problem
                        findFixForFile refusedErrorFixes source restOfErrors

                    Just (Fix.Successful fixedSource) ->
                        -- Return error and the result of the fix otherwise
                        Just ( error, fixedSource )


applyFixFromError : Source -> Review.Error -> Maybe FixResult
applyFixFromError source error =
    error
        |> Review.errorFixes
        |> Maybe.map (\fixes -> Fix.fix fixes source)


fromReviewErrors : Dict String ParsedFile -> List Review.Error -> List ( RawFile, List Reporter.Error )
fromReviewErrors files errors =
    files
        |> Dict.values
        |> List.map
            (\file ->
                ( { path = file.path, source = file.source }
                , errors
                    |> List.filter (\error -> file.path == Review.errorFilePath error)
                    |> List.map fromReviewError
                )
            )
        |> List.filter (\( file, fileErrors ) -> not <| List.isEmpty fileErrors)


fromReviewError : Review.Error -> Reporter.Error
fromReviewError error =
    { moduleName = Review.errorModuleName error
    , ruleName = Review.errorRuleName error
    , message = Review.errorMessage error
    , details = Review.errorDetails error
    , range = Review.errorRange error
    , hasFix = Review.errorFixes error /= Nothing
    }



-- ENCODING


{-| Encode texts to a JSON value.
-}
encodeReport : List Reporter.TextContent -> Encode.Value
encodeReport texts =
    texts
        |> Encode.list encodeReportPart


encodeReportPart : Reporter.TextContent -> Encode.Value
encodeReportPart { str, color, backgroundColor } =
    Encode.object
        [ ( "string", Encode.string str )
        , ( "color"
          , case color of
                Just ( red, green, blue ) ->
                    Encode.list Encode.int [ red, green, blue ]

                Nothing ->
                    Encode.null
          )
        , ( "backgroundColor"
          , case backgroundColor of
                Just ( red, green, blue ) ->
                    Encode.list Encode.int [ red, green, blue ]

                Nothing ->
                    Encode.null
          )
        ]



-- REVIEWING


subscriptions : Sub Msg
subscriptions =
    Sub.batch
        [ collectFile ReceivedFile
        , collectElmJson ReceivedElmJson
        , startReview (\_ -> GotRequestToReview)
        , userConfirmedFix UserConfirmedFix
        ]

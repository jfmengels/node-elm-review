port module Elm.Review.Main exposing (main)

import Elm.Project
import Elm.Review.File as File exposing (File)
import Elm.Review.RefusedErrorFixes as RefusedErrorFixes exposing (RefusedErrorFixes)
import Json.Decode as Decode
import Json.Encode as Encode
import Lint
import Lint.Fix as Fix exposing (FixResult)
import Lint.Project
import Reporter
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
    { files : List File
    , project : Lint.Project.Project
    , fixMode : FixMode
    , reviewErrors : List ( File, List Lint.Error )
    , refusedErrorFixes : RefusedErrorFixes
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
              , project = Lint.Project.new
              , fixMode = fixMode
              , reviewErrors = []
              , errorAwaitingConfirmation = Nothing
              , refusedErrorFixes = RefusedErrorFixes.empty
              }
            , Cmd.none
            )

        Err _ ->
            ( { files = []
              , project = Lint.Project.new
              , fixMode = DontFix
              , reviewErrors = []
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
        ReceivedFile rawFile ->
            case Decode.decodeValue File.decode rawFile of
                Ok file ->
                    ( { model | files = file :: model.files }
                    , acknowledgeFileReceipt file.path
                    )

                Err err ->
                    ( model, Cmd.none )

        ReceivedElmJson rawElmJson ->
            case Decode.decodeValue Elm.Project.decoder rawElmJson of
                Ok elmJson ->
                    ( { model | project = Lint.Project.withElmJson elmJson model.project }
                    , Cmd.none
                    )

                Err err ->
                    ( model, Cmd.none )

        GotRequestToReview ->
            runReview model

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
                        |> reReviewFile updatedFile
                        |> fixOneByOne

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


reReviewFile : File -> Model -> Model
reReviewFile updatedFile model =
    { model | reviewErrors = replaceFileErrors updatedFile (review model.project updatedFile) model.reviewErrors }


replaceFileErrors : File -> List Lint.Error -> List ( File, List Lint.Error ) -> List ( File, List Lint.Error )
replaceFileErrors updatedFile errorsForFile allErrors =
    case allErrors of
        [] ->
            []

        (( file, _ ) as fileAndErrors) :: restOfErrors ->
            if file.path == updatedFile.path then
                ( updatedFile, errorsForFile ) :: restOfErrors

            else
                fileAndErrors :: replaceFileErrors updatedFile errorsForFile restOfErrors


refuseError : Lint.Error -> Model -> Model
refuseError error model =
    { model | refusedErrorFixes = RefusedErrorFixes.insert error model.refusedErrorFixes }


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


runReview : Model -> ( Model, Cmd msg )
runReview model =
    let
        reviewErrors : List ( File, List Lint.Error )
        reviewErrors =
            model.files
                |> List.map (\file -> ( file, review model.project file ))

        modelWithErrors : Model
        modelWithErrors =
            { model | reviewErrors = reviewErrors }
    in
    case modelWithErrors.fixMode of
        DontFix ->
            makeReport modelWithErrors

        Fix ->
            fixOneByOne modelWithErrors


makeReport : Model -> ( Model, Cmd msg )
makeReport model =
    let
        success : Bool
        success =
            model.reviewErrors
                |> List.concatMap Tuple.second
                |> List.length
                |> (==) 0

        report : Encode.Value
        report =
            model.reviewErrors
                |> fromReviewErrors
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
    case findFix model.refusedErrorFixes model.reviewErrors of
        Just ( file, error, fixedSource ) ->
            ( { model | errorAwaitingConfirmation = Just error }
            , askConfirmationToFix
                { file = File.encode { file | source = fixedSource }
                , error = Lint.errorMessage error
                , confirmationMessage =
                    Reporter.formatFixProposal file (fromReviewError error) fixedSource
                        |> encodeReport
                }
            )

        Nothing ->
            makeReport model


findFix : RefusedErrorFixes -> List ( File, List Lint.Error ) -> Maybe ( File, Lint.Error, String )
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


findFixForFile : RefusedErrorFixes -> String -> List Lint.Error -> Maybe ( Lint.Error, String )
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


applyFixFromError : Source -> Lint.Error -> Maybe FixResult
applyFixFromError source error =
    error
        |> Lint.errorFixes
        |> Maybe.map (\fixes -> Fix.fix fixes source)


fromReviewErrors : List ( File, List Lint.Error ) -> List ( File, List Reporter.Error )
fromReviewErrors errors =
    (List.map <| Tuple.mapSecond <| List.map fromReviewError) errors


fromReviewError : Lint.Error -> Reporter.Error
fromReviewError error =
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


review : Lint.Project.Project -> File -> List Lint.Error
review project file =
    Lint.lint config project file


subscriptions : Sub Msg
subscriptions =
    Sub.batch
        [ collectFile ReceivedFile
        , collectElmJson ReceivedElmJson
        , startReview (\_ -> GotRequestToReview)
        , userConfirmedFix UserConfirmedFix
        ]

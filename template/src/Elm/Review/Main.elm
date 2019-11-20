port module Elm.Review.Main exposing (main)

import Dict exposing (Dict)
import Elm.Docs
import Elm.Project
import Elm.Review.File as File
import Elm.Review.RefusedErrorFixes as RefusedErrorFixes exposing (RefusedErrorFixes)
import Json.Decode as Decode
import Json.Encode as Encode
import Reporter
import Review
import Review.File exposing (ParsedFile, RawFile)
import Review.Fix as Fix exposing (FixResult)
import Review.Project as Project exposing (Project)
import Review.Rule as Rule exposing (Rule)
import ReviewConfig exposing (config)



-- PORTS


port collectFile : (RawFile -> msg) -> Sub msg


port collectElmJson : (Decode.Value -> msg) -> Sub msg


port collectDependencies : (List { packageName : String, version : String, docsJson : String } -> msg) -> Sub msg


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
    , rules : List Rule
    , project : Project
    , fixMode : FixMode
    , reviewErrors : List Rule.Error
    , parseErrors : List ( RawFile, List Reporter.Error )
    , refusedErrorFixes : RefusedErrorFixes
    , errorAwaitingConfirmation : Maybe Rule.Error
    }


type FixMode
    = DontFix
    | Fix


init : Flags -> ( Model, Cmd msg )
init flags =
    let
        ( fixMode, cmd ) =
            case Decode.decodeValue decodeFlags flags of
                Ok fixMode_ ->
                    ( fixMode_, Cmd.none )

                Err _ ->
                    ( DontFix, abort <| "Problem decoding the flags when running the elm-review runner" )
    in
    ( { files = Dict.empty
      , rules = config
      , project = Project.new
      , fixMode = fixMode
      , reviewErrors = []
      , parseErrors = []
      , errorAwaitingConfirmation = Nothing
      , refusedErrorFixes = RefusedErrorFixes.empty
      }
    , cmd
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
    = ReceivedFile RawFile
    | ReceivedElmJson Decode.Value
    | ReceivedDependencies (List { packageName : String, version : String, docsJson : String })
    | GotRequestToReview
    | UserConfirmedFix Decode.Value


type alias Source =
    String


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ReceivedFile rawFile ->
            case Review.parseFile rawFile of
                Ok parsedFile ->
                    ( { model | files = Dict.insert parsedFile.path parsedFile model.files }
                    , acknowledgeFileReceipt parsedFile.path
                    )

                Err parseError ->
                    ( { model | parseErrors = ( rawFile, [ fromReviewError parseError ] ) :: model.parseErrors }
                    , acknowledgeFileReceipt rawFile.path
                    )

        ReceivedElmJson rawElmJson ->
            case Decode.decodeValue Elm.Project.decoder rawElmJson of
                Ok elmJson ->
                    ( { model | project = Project.withElmJson elmJson model.project }
                    , Cmd.none
                    )

                Err err ->
                    ( model, Cmd.none )

        ReceivedDependencies dependencies ->
            let
                project : Project
                project =
                    List.foldl
                        (\{ packageName, version, docsJson } project_ ->
                            case Decode.decodeString (Decode.list Elm.Docs.decoder) docsJson of
                                Ok modules ->
                                    Project.withDependency
                                        { packageName = packageName, version = version, modules = modules }
                                        project_

                                Err _ ->
                                    project_
                        )
                        model.project
                        dependencies
            in
            ( { model | project = project }, Cmd.none )

        GotRequestToReview ->
            runReview model
                |> reportOrFix

        UserConfirmedFix confirmation ->
            case Decode.decodeValue confirmationDecoder confirmation of
                Ok (Accepted rawFile) ->
                    case Review.parseFile rawFile of
                        Ok parsedFile ->
                            { model
                                | errorAwaitingConfirmation = Nothing
                                , files = Dict.insert parsedFile.path parsedFile model.files
                            }
                                |> runReview
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


replaceFileErrors : ParsedFile -> List Rule.Error -> List ( ParsedFile, List Rule.Error ) -> List ( ParsedFile, List Rule.Error )
replaceFileErrors updatedFile errorsForFile allErrors =
    case allErrors of
        [] ->
            []

        (( file, _ ) as fileAndErrors) :: restOfErrors ->
            if file.path == updatedFile.path then
                ( updatedFile, errorsForFile ) :: restOfErrors

            else
                fileAndErrors :: replaceFileErrors updatedFile errorsForFile restOfErrors


refuseError : Rule.Error -> Model -> Model
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


runReview : Model -> Model
runReview model =
    let
        ( reviewErrors, rules ) =
            Review.reviewFiles model.rules model.project (Dict.values model.files)
    in
    { model | reviewErrors = reviewErrors, rules = rules }


reportOrFix : Model -> ( Model, Cmd msg )
reportOrFix model =
    case model.fixMode of
        DontFix ->
            makeReport model

        Fix ->
            fixOneByOne model


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
    case findFix model.refusedErrorFixes model.files model.reviewErrors of
        Just ( file, error, fixedSource ) ->
            ( { model | errorAwaitingConfirmation = Just error }
            , askConfirmationToFix
                { file = File.encode { file | source = fixedSource }
                , error = Rule.errorMessage error
                , confirmationMessage =
                    Reporter.formatFixProposal
                        { path = file.path, source = file.source }
                        (fromReviewError error)
                        fixedSource
                        |> encodeReport
                }
            )

        Nothing ->
            makeReport model


findFix : RefusedErrorFixes -> Dict String ParsedFile -> List Rule.Error -> Maybe ( ParsedFile, Rule.Error, String )
findFix refusedErrorFixes files errors =
    case errors of
        [] ->
            Nothing

        error :: restOfErrors ->
            if RefusedErrorFixes.member error refusedErrorFixes then
                findFix refusedErrorFixes files restOfErrors

            else
                case Dict.get (Rule.errorFilePath error) files of
                    Nothing ->
                        findFix refusedErrorFixes files restOfErrors

                    Just file ->
                        case applyFixFromError error file.source of
                            Nothing ->
                                findFix refusedErrorFixes files restOfErrors

                            Just (Fix.Errored _) ->
                                -- Ignore error if applying the fix results in a problem
                                findFix refusedErrorFixes files restOfErrors

                            Just (Fix.Successful fixedSource) ->
                                -- Return error and the result of the fix otherwise
                                Just ( file, error, fixedSource )


applyFixFromError : Rule.Error -> Source -> Maybe FixResult
applyFixFromError error source =
    error
        |> Rule.errorFixes
        |> Maybe.map (\fixes -> Fix.fix fixes source)


fromReviewErrors : Dict String ParsedFile -> List Rule.Error -> List ( RawFile, List Reporter.Error )
fromReviewErrors files errors =
    files
        |> Dict.values
        |> List.map
            (\file ->
                ( { path = file.path, source = file.source }
                , errors
                    |> List.filter (\error -> file.path == Rule.errorFilePath error)
                    |> List.map fromReviewError
                )
            )
        |> List.filter (\( file, fileErrors ) -> not <| List.isEmpty fileErrors)


fromReviewError : Rule.Error -> Reporter.Error
fromReviewError error =
    { ruleName = Rule.errorRuleName error
    , message = Rule.errorMessage error
    , details = Rule.errorDetails error
    , range = Rule.errorRange error
    , hasFix = Rule.errorFixes error /= Nothing
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
        , collectDependencies ReceivedDependencies
        , startReview (\_ -> GotRequestToReview)
        , userConfirmedFix UserConfirmedFix
        ]

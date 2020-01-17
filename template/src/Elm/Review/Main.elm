port module Elm.Review.Main exposing (main)

import Dict exposing (Dict)
import Elm.Docs
import Elm.Project
import Elm.Review.File as File
import Elm.Review.RefusedErrorFixes as RefusedErrorFixes exposing (RefusedErrorFixes)
import Elm.Syntax.File
import Json.Decode as Decode
import Json.Encode as Encode
import Reporter
import Review
import Review.Fix as Fix exposing (FixResult)
import Review.Project as Project exposing (ParsedFile, Project)
import Review.Rule as Rule exposing (Rule)
import ReviewConfig exposing (config)



-- PORTS


port collectFile : (Decode.Value -> msg) -> Sub msg


port removeFile : (String -> msg) -> Sub msg


port collectElmJson : (Decode.Value -> msg) -> Sub msg


port collectDependencies : (List { packageName : String, version : String, docsJson : String } -> msg) -> Sub msg


port cacheFile : Encode.Value -> Cmd msg


port acknowledgeFileReceipt : String -> Cmd msg


port startReview : (Bool -> msg) -> Sub msg


port reviewReport : { success : Bool, report : Encode.Value } -> Cmd msg


port userConfirmedFix : (Decode.Value -> msg) -> Sub msg


port askConfirmationToFix : { file : Encode.Value, error : String, confirmationMessage : Encode.Value } -> Cmd msg


port askForFixConfirmationStatus : (() -> msg) -> Sub msg


port fixConfirmationStatus : Bool -> Cmd msg


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
    { rules : List Rule
    , project : Project
    , fixMode : FixMode
    , reviewErrors : List Rule.Error
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
    ( { rules = config
      , project = Project.new
      , fixMode = fixMode
      , reviewErrors = []
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
    = ReceivedFile Decode.Value
    | RemovedFile String
    | ReceivedElmJson Decode.Value
    | ReceivedDependencies (List { packageName : String, version : String, docsJson : String })
    | GotRequestToReview
    | UserConfirmedFix Decode.Value
    | RequestedToKnowIfAFixConfirmationIsExpected


type alias Source =
    String


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ReceivedFile value ->
            case Decode.decodeValue File.decode value of
                Ok rawFile ->
                    case rawFile.ast of
                        Nothing ->
                            let
                                project : Project
                                project =
                                    Project.withModule { path = rawFile.path, source = rawFile.source } model.project
                            in
                            ( { model | project = project }
                            , Cmd.batch
                                [ acknowledgeFileReceipt rawFile.path
                                , sendFileToBeCached project rawFile.source
                                ]
                            )

                        Just ast ->
                            ( { model
                                | project =
                                    Project.withParsedModule
                                        { path = rawFile.path
                                        , source = rawFile.source
                                        , ast = ast
                                        }
                                        model.project
                              }
                            , acknowledgeFileReceipt rawFile.path
                            )

                Err err ->
                    ( model, abort <| Decode.errorToString err )

        RemovedFile path ->
            ( { model | project = Project.removeModule path model.project }, Cmd.none )

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
                        (Project.removeDependencies model.project)
                        dependencies
            in
            ( { model | project = project }, Cmd.none )

        GotRequestToReview ->
            { model | project = Project.precomputeModuleGraph model.project }
                |> runReview
                |> reportOrFix

        UserConfirmedFix confirmation ->
            case Decode.decodeValue confirmationDecoder confirmation of
                Ok (Accepted rawFile) ->
                    let
                        newProject : Project
                        newProject =
                            Project.withModule { path = rawFile.path, source = rawFile.source } model.project
                    in
                    if List.length (Project.filesThatFailedToParse newProject) > List.length (Project.filesThatFailedToParse model.project) then
                        -- There is a new file that failed to parse in the
                        -- project when we updated the fixed file. This means
                        -- that our fix introduced a syntactical regression that
                        -- we were not successful in preventing earlier.
                        ( model
                          -- TODO Improve abort message
                        , abort <| "File " ++ rawFile.path ++ " could not be read. An incorrect fix may have been introduced into this file..."
                        )

                    else
                        { model | project = newProject }
                            |> runReview
                            |> fixOneByOne
                            |> Tuple.mapSecond
                                (\cmd ->
                                    Cmd.batch
                                        [ cmd
                                        , sendFileToBeCached newProject rawFile.source
                                        ]
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

        RequestedToKnowIfAFixConfirmationIsExpected ->
            ( model, fixConfirmationStatus (model.errorAwaitingConfirmation /= Nothing) )


sendFileToBeCached : Project -> String -> Cmd msg
sendFileToBeCached project source =
    case
        project
            |> Project.modules
            |> find (\module_ -> module_.source == source)
    of
        Just { ast } ->
            Encode.object
                [ ( "source", Encode.string source )
                , ( "ast", Elm.Syntax.File.encode ast )
                ]
                |> cacheFile

        Nothing ->
            Cmd.none


{-| Find the first element that satisfies a predicate and return
Just that element. If none match, return Nothing.
find (\\num -> num > 5) [2, 4, 6, 8] == Just 6
-}
find : (a -> Bool) -> List a -> Maybe a
find predicate list =
    case list of
        [] ->
            Nothing

        first :: rest ->
            if predicate first then
                Just first

            else
                find predicate rest


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
    = Accepted { path : String, source : String, ast : Maybe Elm.Syntax.File.File }
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
            Review.review model.rules model.project
    in
    { model
        | reviewErrors = reviewErrors
        , rules = rules
        , errorAwaitingConfirmation = Nothing
    }


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
        errors : List ( { path : String, source : String }, List Reporter.Error )
        errors =
            fromReviewErrors model.project model.reviewErrors

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
    let
        files : Dict String ParsedFile
        files =
            Project.modules model.project
                |> List.map (\module_ -> ( module_.path, module_ ))
                |> Dict.fromList
    in
    case findFix model.refusedErrorFixes files model.reviewErrors of
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


fromReviewErrors : Project -> List Rule.Error -> List ( { path : String, source : String }, List Reporter.Error )
fromReviewErrors project errors =
    let
        files : List { path : String, source : String }
        files =
            List.concat
                [ project
                    |> Project.modules
                    |> List.map (\file -> { path = file.path, source = file.source })
                , Project.filesThatFailedToParse project
                ]
    in
    files
        |> List.map
            (\file ->
                ( file
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
        , removeFile RemovedFile
        , collectElmJson ReceivedElmJson
        , collectDependencies ReceivedDependencies
        , startReview (\_ -> GotRequestToReview)
        , userConfirmedFix UserConfirmedFix
        , askForFixConfirmationStatus (always RequestedToKnowIfAFixConfirmationIsExpected)
        ]

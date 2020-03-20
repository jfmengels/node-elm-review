port module Elm.Review.Main exposing (main)

import Dict exposing (Dict)
import Elm.Docs
import Elm.Project
import Elm.Review.File
import Elm.Review.RefusedErrorFixes as RefusedErrorFixes exposing (RefusedErrorFixes)
import Elm.Review.Reporter as Reporter
import Elm.Syntax.File
import Elm.Syntax.Range as Range
import Json.Decode as Decode
import Json.Encode as Encode
import Review.Fix as Fix exposing (FixResult)
import Review.Project as Project exposing (Project, ProjectModule)
import Review.Project.Dependency as Dependency exposing (Dependency)
import Review.Rule as Rule exposing (Rule)
import ReviewConfig exposing (config)



-- PORTS


port collectFile : (Decode.Value -> msg) -> Sub msg


port removeFile : (String -> msg) -> Sub msg


port collectElmJson : (Decode.Value -> msg) -> Sub msg


port collectDependencies : (Decode.Value -> msg) -> Sub msg


port cacheFile : Encode.Value -> Cmd msg


port acknowledgeFileReceipt : String -> Cmd msg


port startReview : (Bool -> msg) -> Sub msg


port reviewReport : Encode.Value -> Cmd msg


port userConfirmedFix : (Decode.Value -> msg) -> Sub msg


port askConfirmationToFix : Encode.Value -> Cmd msg


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

    -- FIX
    , refusedErrorFixes : RefusedErrorFixes
    , errorAwaitingConfirmation : AwaitingConfirmation

    -- FIX ALL
    , fixAllResultProject : Project
    , fixAllErrors : Dict String (List Reporter.Error)
    }


type AwaitingConfirmation
    = NotAwaiting
    | AwaitingError Rule.Error
    | AwaitingFixAll


type FixMode
    = DontFix
    | Fix
    | FixAll


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
      , fixAllResultProject = Project.new
      , fixMode = fixMode
      , reviewErrors = []
      , refusedErrorFixes = RefusedErrorFixes.empty
      , errorAwaitingConfirmation = NotAwaiting
      , fixAllErrors = Dict.empty
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

                    "fixAll" ->
                        Decode.succeed FixAll

                    _ ->
                        Decode.fail <| "I could not understand the following fix mode: " ++ fixMode
            )



-- UPDATE


type Msg
    = ReceivedFile Decode.Value
    | RemovedFile String
    | ReceivedElmJson Decode.Value
    | ReceivedDependencies Decode.Value
    | GotRequestToReview
    | UserConfirmedFix Decode.Value
    | RequestedToKnowIfAFixConfirmationIsExpected


type alias Source =
    String


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ReceivedFile value ->
            case Decode.decodeValue Elm.Review.File.decode value of
                Ok rawFile ->
                    case rawFile.ast of
                        Nothing ->
                            let
                                project : Project
                                project =
                                    Project.addModule { path = rawFile.path, source = rawFile.source } model.project
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
                                    Project.addParsedModule
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
            let
                elmJsonDecoder : Decode.Decoder { path : String, raw : String, project : Elm.Project.Project }
                elmJsonDecoder =
                    Decode.map3 (\path raw project -> { path = path, raw = raw, project = project })
                        (Decode.field "path" Decode.string)
                        (Decode.field "raw" Decode.string)
                        (Decode.field "project" Elm.Project.decoder)
            in
            case Decode.decodeValue elmJsonDecoder rawElmJson of
                Ok elmJson ->
                    ( { model | project = Project.addElmJson elmJson model.project }
                    , Cmd.none
                    )

                Err err ->
                    ( model, Cmd.none )

        ReceivedDependencies json ->
            let
                dependencyDecoder : Decode.Decoder Dependency
                dependencyDecoder =
                    Decode.map3 Dependency.create
                        (Decode.field "name" Decode.string)
                        (Decode.field "elmJson" Elm.Project.decoder)
                        (Decode.field "docsJson" <| Decode.list Elm.Docs.decoder)
            in
            case Decode.decodeValue (Decode.list dependencyDecoder) json of
                Err decodeError ->
                    ( model
                    , abort <|
                        "I encountered an error when reading the dependencies of the project. I suggest opening a bug report at https://github.com/jfmengels/node-elm-review/issues."
                            ++ Decode.errorToString decodeError
                    )

                Ok dependencies ->
                    ( { model
                        | project =
                            List.foldl
                                Project.addDependency
                                (Project.removeDependencies model.project)
                                dependencies
                      }
                    , Cmd.none
                    )

        GotRequestToReview ->
            { model
                | project = Project.precomputeModuleGraph model.project
                , fixAllErrors = Dict.empty
            }
                |> runReview
                |> reportOrFix

        UserConfirmedFix confirmation ->
            case Decode.decodeValue confirmationDecoder confirmation of
                Ok (Accepted rawFiles) ->
                    let
                        newProject : Project
                        newProject =
                            List.foldl
                                (\file project -> Project.addModule { path = file.path, source = file.source } project)
                                model.project
                                rawFiles
                    in
                    if List.length (Project.filesThatFailedToParse newProject) > List.length (Project.filesThatFailedToParse model.project) then
                        -- There is a new file that failed to parse in the
                        -- project when we updated the fixed file. This means
                        -- that our fix introduced a syntactical regression that
                        -- we were not successful in preventing earlier.
                        ( model
                          -- TODO Improve abort message
                        , abort <| "One file among " ++ (String.join ", " <| List.map .path rawFiles) ++ " could not be read. An incorrect fix may have been introduced into one of these files..."
                        )

                    else
                        { model | project = newProject, fixAllErrors = Dict.empty }
                            |> runReview
                            |> reportOrFix
                            |> Tuple.mapSecond
                                (\cmd ->
                                    (cmd :: List.map (.source >> sendFileToBeCached newProject) rawFiles)
                                        |> Cmd.batch
                                )

                Ok Refused ->
                    case model.errorAwaitingConfirmation of
                        AwaitingError error ->
                            model
                                |> refuseError error
                                |> fixOneByOne

                        AwaitingFixAll ->
                            { model | errorAwaitingConfirmation = NotAwaiting }
                                |> runReview
                                |> makeReport

                        NotAwaiting ->
                            fixOneByOne model

                Err err ->
                    ( model, abort <| Decode.errorToString err )

        RequestedToKnowIfAFixConfirmationIsExpected ->
            ( model, fixConfirmationStatus (model.errorAwaitingConfirmation /= NotAwaiting) )


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


replaceFileErrors : ProjectModule -> List Rule.Error -> List ( ProjectModule, List Rule.Error ) -> List ( ProjectModule, List Rule.Error )
replaceFileErrors module_ errorsForFile allErrors =
    case allErrors of
        [] ->
            []

        (( file, _ ) as fileAndErrors) :: restOfErrors ->
            if file.path == module_.path then
                ( module_, errorsForFile ) :: restOfErrors

            else
                fileAndErrors :: replaceFileErrors module_ errorsForFile restOfErrors


refuseError : Rule.Error -> Model -> Model
refuseError error model =
    { model | refusedErrorFixes = RefusedErrorFixes.insert error model.refusedErrorFixes }


type Confirmation
    = Accepted (List { path : String, source : String, ast : Maybe Elm.Syntax.File.File })
    | Refused


confirmationDecoder : Decode.Decoder Confirmation
confirmationDecoder =
    Decode.field "answer" Decode.bool
        |> Decode.andThen
            (\accepted ->
                if accepted then
                    Decode.field "files" (Decode.list Elm.Review.File.decode)
                        |> Decode.map Accepted

                else
                    Decode.succeed Refused
            )


runReview : Model -> Model
runReview model =
    let
        ( reviewErrors, rules ) =
            Rule.review model.rules model.project
    in
    { model
        | reviewErrors = reviewErrors
        , rules = rules
        , errorAwaitingConfirmation = NotAwaiting
    }


reportOrFix : Model -> ( Model, Cmd msg )
reportOrFix model =
    case model.fixMode of
        DontFix ->
            makeReport model

        Fix ->
            fixOneByOne model

        FixAll ->
            fixAll model


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
    , [ ( "success", Encode.bool success )
      , ( "report", report )
      , ( "json", Encode.list encodeError model.reviewErrors )
      ]
        |> Encode.object
        |> reviewReport
    )


encodeError : Rule.Error -> Encode.Value
encodeError error =
    Encode.object
        [ ( "message", Encode.string <| Rule.errorMessage error )
        , ( "ruleName", Encode.string <| Rule.errorRuleName error )
        , ( "filePath", Encode.string <| Rule.errorFilePath error )
        , ( "details", Encode.list Encode.string <| Rule.errorDetails error )
        , ( "range", Range.encode <| Rule.errorRange error )
        ]


fixOneByOne : Model -> ( Model, Cmd msg )
fixOneByOne model =
    let
        files : Dict String ProjectModule
        files =
            Project.modules model.project
                |> List.map (\module_ -> ( module_.path, module_ ))
                |> Dict.fromList
    in
    case findFix model.refusedErrorFixes files model.reviewErrors of
        Just ( file, error, fixedSource ) ->
            ( { model | errorAwaitingConfirmation = AwaitingError error }
            , [ ( "confirmationMessage"
                , Reporter.formatFixProposal
                    { path = file.path, source = file.source }
                    (fromReviewError error)
                    fixedSource
                    |> encodeReport
                )
              , ( "changedFiles", Encode.list encodeChangedFile [ { path = file.path, source = fixedSource } ] )
              , ( "error", Encode.string <| Rule.errorMessage error )
              ]
                |> Encode.object
                |> askConfirmationToFix
            )

        Nothing ->
            makeReport model


fixAll : Model -> ( Model, Cmd msg )
fixAll model =
    case applyAllFixes model of
        Just newModel ->
            case diff model.project newModel.project of
                [] ->
                    makeReport newModel

                diffs ->
                    let
                        changedFiles : List { path : String, source : String, fixedSource : String, errors : List Reporter.Error }
                        changedFiles =
                            List.map
                                (\{ module_, fixedSource } ->
                                    { path = module_.path
                                    , source = module_.source
                                    , fixedSource = fixedSource
                                    , errors =
                                        Dict.get module_.path newModel.fixAllErrors
                                            |> Maybe.withDefault []
                                    }
                                )
                                diffs

                        confirmationMessage : Encode.Value
                        confirmationMessage =
                            changedFiles
                                |> Reporter.formatFixProposals
                                |> encodeReport
                    in
                    ( { newModel
                        | project = model.project
                        , fixAllResultProject = newModel.project
                        , errorAwaitingConfirmation = AwaitingFixAll
                      }
                    , askConfirmationToFix
                        (Encode.object
                            [ ( "confirmationMessage", confirmationMessage )
                            , ( "changedFiles"
                              , changedFiles
                                    |> List.map (\file -> { path = file.path, source = file.fixedSource })
                                    |> Encode.list encodeChangedFile
                              )
                            ]
                        )
                    )

        Nothing ->
            ( model
            , abort "Got an error while trying to fix all automatic fixes. One of them made the code invalid. I suggest fixing the errors manually, or using `--fix` but with a lot of precaution."
            )


encodeChangedFile : { path : String, source : String } -> Encode.Value
encodeChangedFile changedFile =
    Encode.object
        [ ( "path", Encode.string changedFile.path )
        , ( "source", Encode.string changedFile.source )
        ]


applyAllFixes : Model -> Maybe Model
applyAllFixes model =
    let
        files : Dict String ProjectModule
        files =
            Project.modules model.project
                |> List.map (\module_ -> ( module_.path, module_ ))
                |> Dict.fromList
    in
    case findFix model.refusedErrorFixes files model.reviewErrors of
        Just ( file, error, fixedSource ) ->
            let
                newProject : Project
                newProject =
                    Project.addModule { path = file.path, source = fixedSource } model.project
            in
            if List.length (Project.filesThatFailedToParse newProject) > List.length (Project.filesThatFailedToParse model.project) then
                -- There is a new file that failed to parse in the
                -- project when we updated the fixed file. This means
                -- that our fix introduced a syntactical regression that
                -- we were not successful in preventing earlier.
                Nothing

            else
                { model | project = newProject }
                    |> addFixedErrorForFile file.path error
                    |> runReview
                    |> applyAllFixes

        Nothing ->
            Just model


addFixedErrorForFile : String -> Rule.Error -> Model -> Model
addFixedErrorForFile path error model =
    let
        errorsForFile : List Reporter.Error
        errorsForFile =
            fromReviewError error
                :: (Dict.get path model.fixAllErrors
                        |> Maybe.withDefault []
                   )
    in
    { model | fixAllErrors = Dict.insert path errorsForFile model.fixAllErrors }


findFix : RefusedErrorFixes -> Dict String ProjectModule -> List Rule.Error -> Maybe ( ProjectModule, Rule.Error, String )
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


diff : Project -> Project -> List { module_ : ProjectModule, fixedSource : String }
diff before after =
    let
        beforeModules : Dict String ProjectModule
        beforeModules =
            before
                |> Project.modules
                |> List.map (\mod -> ( mod.path, mod ))
                |> Dict.fromList

        fixedSources : Dict String String
        fixedSources =
            after
                |> Project.modules
                |> List.map (\mod -> ( mod.path, mod.source ))
                |> Dict.fromList
    in
    Dict.merge
        (\_ _ acc -> acc)
        (\_ beforeModule fixedSource acc ->
            if beforeModule.source /= fixedSource then
                { module_ = beforeModule, fixedSource = fixedSource } :: acc

            else
                acc
        )
        (\_ _ acc -> acc)
        beforeModules
        fixedSources
        []


fromReviewErrors : Project -> List Rule.Error -> List ( { path : String, source : String }, List Reporter.Error )
fromReviewErrors project errors =
    let
        files : List { path : String, source : String }
        files =
            List.concat
                [ project
                    |> Project.modules
                    |> List.map (\file -> { path = file.path, source = file.source })
                , [ { path = "GLOBAL ERROR", source = "" } ]
                , case Project.elmJson project of
                    Just { path, raw } ->
                        [ { path = path, source = raw } ]

                    Nothing ->
                        []
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

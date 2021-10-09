port module Elm.Review.Main exposing (main)

import Dict exposing (Dict)
import Elm.Constraint
import Elm.Docs
import Elm.Package
import Elm.Project
import Elm.Review.AstCodec as AstCodec
import Elm.Review.File
import Elm.Review.Progress as Progress
import Elm.Review.RefusedErrorFixes as RefusedErrorFixes exposing (RefusedErrorFixes)
import Elm.Review.Reporter as Reporter
import Elm.Review.Vendor.Levenshtein as Levenshtein
import Elm.Review.Vendor.List.Extra as ListExtra
import Elm.Syntax.File
import Elm.Syntax.Range as Range exposing (Range)
import Elm.Version
import Json.Decode as Decode
import Json.Encode as Encode
import Review.Fix as Fix exposing (Fix)
import Review.Project as Project exposing (Project)
import Review.Project.Dependency as Dependency exposing (Dependency)
import Review.Rule as Rule exposing (Rule)
import ReviewConfig exposing (config)
import Set exposing (Set)



-- PORTS


port collectFile : (Decode.Value -> msg) -> Sub msg


port removeFile : (String -> msg) -> Sub msg


port collectElmJson : (Decode.Value -> msg) -> Sub msg


port collectReadme : (Decode.Value -> msg) -> Sub msg


port collectDependencies : (Decode.Value -> msg) -> Sub msg


port collectSuppressedErrors : (Decode.Value -> msg) -> Sub msg


port collectLinks : (Decode.Value -> msg) -> Sub msg


port cacheFile : Encode.Value -> Cmd msg


port acknowledgeFileReceipt : Encode.Value -> Cmd msg


port startReview : (() -> msg) -> Sub msg


port reviewReport : Encode.Value -> Cmd msg


port startGeneratingSuppressions : (() -> msg) -> Sub msg


port suppressionsResponse : Encode.Value -> Cmd msg


port userConfirmedFix : (Decode.Value -> msg) -> Sub msg


port askConfirmationToFix : Encode.Value -> Cmd msg


port askForFixConfirmationStatus : (() -> msg) -> Sub msg


port fixConfirmationStatus : Bool -> Cmd msg


port abort : String -> Cmd msg


port abortWithDetails : { title : String, message : String } -> Cmd msg


port abortForConfigurationErrors : Encode.Value -> Cmd msg



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
    , projectData : Maybe Rule.ProjectData
    , links : Dict String String
    , fixMode : FixMode
    , detailsMode : Reporter.DetailsMode
    , reportMode : ReportMode
    , reviewErrors : List Rule.ReviewError
    , reviewErrorsAfterSuppression : List Rule.ReviewError
    , suppressedErrors : SuppressedErrorsDict
    , errorsHaveBeenFixedPreviously : Bool
    , ignoreProblematicDependencies : Bool

    -- FIX
    , refusedErrorFixes : RefusedErrorFixes
    , errorAwaitingConfirmation : AwaitingConfirmation

    -- FIX ALL
    , fixAllResultProject : Project
    , fixAllErrors : Dict String (List Reporter.Error)
    , logger : Progress.Console
    }


type AwaitingConfirmation
    = NotAwaiting
    | AwaitingError Rule.ReviewError
    | AwaitingFixAll


type FixMode
    = Mode_DontFix
    | Mode_Fix
    | Mode_FixAll


type ReportMode
    = HumanReadable
    | Json


init : Flags -> ( Model, Cmd msg )
init rawFlags =
    let
        ( flags, cmd ) =
            case Decode.decodeValue decodeFlags rawFlags of
                Ok decodedFlags ->
                    ( decodedFlags, Cmd.none )

                Err error ->
                    ( { fixMode = Mode_DontFix
                      , reportMode = HumanReadable
                      , detailsMode = Reporter.WithoutDetails
                      , ignoreProblematicDependencies = False
                      , rulesFilter = Nothing
                      , ignoredDirs = []
                      , ignoredFiles = []
                      , logger = Progress.dummy
                      }
                    , abort <| "Problem decoding the flags when running the elm-review runner:\n  " ++ Decode.errorToString error
                    )

        ( rules, filterNames ) =
            case flags.rulesFilter of
                Just rulesToEnable ->
                    let
                        ruleNames : Set String
                        ruleNames =
                            List.map Rule.ruleName config
                                |> Set.fromList
                    in
                    ( List.filter (\rule -> Set.member (Rule.ruleName rule) rulesToEnable) config
                    , Set.diff rulesToEnable ruleNames
                        |> Set.toList
                    )

                Nothing ->
                    ( config, [] )
    in
    ( { rules =
            List.map
                (Rule.ignoreErrorsForDirectories flags.ignoredDirs >> Rule.ignoreErrorsForFiles flags.ignoredFiles)
                rules
      , project = Project.new
      , projectData = Nothing
      , links = Dict.empty
      , fixAllResultProject = Project.new
      , fixMode = flags.fixMode
      , detailsMode = flags.detailsMode
      , reportMode = flags.reportMode
      , reviewErrors = []
      , reviewErrorsAfterSuppression = []
      , suppressedErrors = Dict.empty
      , errorsHaveBeenFixedPreviously = False
      , refusedErrorFixes = RefusedErrorFixes.empty
      , errorAwaitingConfirmation = NotAwaiting
      , fixAllErrors = Dict.empty
      , ignoreProblematicDependencies = flags.ignoreProblematicDependencies
      , logger = flags.logger
      }
    , if List.isEmpty config then
        -- TODO Add color/styling to this message. It was taken and adapted from the post-init step message
        abortWithDetails
            { title = "CONFIGURATION IS EMPTY"
            , message =
                """Your configuration contains no rules. You can add rules by editing the ReviewConfig.elm file.

I recommend you take a look at the following documents:
  - How to configure elm-review: https://github.com/jfmengels/elm-review/#Configuration
  - When to write or enable a rule: https://github.com/jfmengels/elm-review/#when-to-write-or-enable-a-rule"""
            }

      else if not (List.isEmpty filterNames) then
        abortWithDetails
            (unknownRulesFilterMessage
                { ruleNames =
                    List.map Rule.ruleName config
                        |> Set.fromList
                        |> Set.toList
                , filterNames = filterNames
                }
            )

      else
        case List.filterMap getConfigurationError config of
            [] ->
                cmd

            configurationErrors ->
                abortForConfigurationErrors <|
                    case flags.reportMode of
                        HumanReadable ->
                            [ { path = Reporter.ConfigurationError
                              , source = Reporter.Source ""
                              , errors = configurationErrors
                              }
                            ]
                                |> Reporter.formatReport Dict.empty flags.detailsMode False
                                |> encodeReport

                        Json ->
                            encodeConfigurationErrors flags.detailsMode configurationErrors
    )


getConfigurationError : Rule -> Maybe Reporter.Error
getConfigurationError rule =
    case Rule.getConfigurationError rule of
        Just configurationError ->
            Just
                { ruleName = Rule.ruleName rule
                , ruleLink = Nothing
                , message = configurationError.message
                , details = configurationError.details
                , range = Range.emptyRange
                , fixesHash = Nothing
                }

        Nothing ->
            Nothing


unknownRulesFilterMessage : { ruleNames : List String, filterNames : List String } -> { title : String, message : String }
unknownRulesFilterMessage { ruleNames, filterNames } =
    let
        unknownRulesMessage : String
        unknownRulesMessage =
            filterNames
                |> List.map (\filterName -> "- " ++ filterName ++ ". Did you mean:\n  - " ++ String.join "\n  - " (closestNames ruleNames filterName))
                |> String.join "\n\n"
    in
    { title = "UNKNOWN FILTERED RULE(S)"
    , message =
        """You requested to only run several rules, but I could not find some of them.

""" ++ unknownRulesMessage
    }


closestNames : List String -> String -> List String
closestNames names name =
    names
        |> List.sortBy (Levenshtein.distance name)
        |> List.take 3


type alias DecodedFlags =
    { fixMode : FixMode
    , detailsMode : Reporter.DetailsMode
    , reportMode : ReportMode
    , ignoreProblematicDependencies : Bool
    , rulesFilter : Maybe (Set String)
    , ignoredDirs : List String
    , ignoredFiles : List String
    , logger : Progress.Console
    }


decodeFlags : Decode.Decoder DecodedFlags
decodeFlags =
    Decode.succeed DecodedFlags
        |> field "fixMode" decodeFix
        |> field "detailsMode" decodeDetailsMode
        |> field "report" decodeReportMode
        |> field "ignoreProblematicDependencies" Decode.bool
        |> field "rulesFilter" decodeRulesFilter
        |> field "ignoredDirs" (Decode.list Decode.string)
        |> field "ignoredFiles" (Decode.list Decode.string)
        |> field "logger" Progress.decoder


field : String -> Decode.Decoder a -> Decode.Decoder (a -> b) -> Decode.Decoder b
field key valDecoder decoder =
    Decode.map2
        (|>)
        (Decode.field key valDecoder)
        decoder


decodeFix : Decode.Decoder FixMode
decodeFix =
    Decode.string
        |> Decode.andThen
            (\fixMode ->
                case fixMode of
                    "dontfix" ->
                        Decode.succeed Mode_DontFix

                    "fix" ->
                        Decode.succeed Mode_Fix

                    "fixAll" ->
                        Decode.succeed Mode_FixAll

                    _ ->
                        Decode.fail <| "I could not understand the following fix mode: " ++ fixMode
            )


decodeDetailsMode : Decode.Decoder Reporter.DetailsMode
decodeDetailsMode =
    Decode.string
        |> Decode.andThen
            (\detailsMode ->
                case detailsMode of
                    "with-details" ->
                        Decode.succeed Reporter.WithDetails

                    "without-details" ->
                        Decode.succeed Reporter.WithoutDetails

                    _ ->
                        Decode.fail <| "I could not understand the following details mode: " ++ detailsMode
            )


decodeReportMode : Decode.Decoder ReportMode
decodeReportMode =
    Decode.string
        |> Decode.andThen
            (\reportMode ->
                case reportMode of
                    "human" ->
                        Decode.succeed HumanReadable

                    "json" ->
                        Decode.succeed Json

                    _ ->
                        Decode.fail <| "I could not understand the following report mode: " ++ reportMode
            )


decodeRulesFilter : Decode.Decoder (Maybe (Set String))
decodeRulesFilter =
    Decode.oneOf
        [ Decode.list Decode.string
            |> Decode.map (Set.fromList >> Just)
        , Decode.null Nothing
        ]



-- UPDATE


type Msg
    = ReceivedFile Decode.Value
    | RemovedFile String
    | ReceivedElmJson Decode.Value
    | ReceivedReadme Decode.Value
    | ReceivedDependencies Decode.Value
    | ReceivedSuppressedErrors Decode.Value
    | ReceivedLinks Decode.Value
    | GotRequestToReview
    | GotRequestToGenerateSuppressionErrors
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
                            , Encode.object
                                [ ( "path", Encode.string rawFile.path )
                                , ( "cacheRequest", cacheFileRequest project rawFile.source )
                                ]
                                |> acknowledgeFileReceipt
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
                            , Encode.object
                                [ ( "path", Encode.string rawFile.path )
                                , ( "cacheRequest", Encode.null )
                                ]
                                |> acknowledgeFileReceipt
                            )

                Err err ->
                    ( model, abort <| Decode.errorToString err )

        RemovedFile path ->
            ( { model | project = Project.removeModule path model.project }, Cmd.none )

        ReceivedElmJson rawElmJson ->
            case Decode.decodeValue elmJsonDecoder rawElmJson of
                Ok elmJson ->
                    ( { model | project = Project.addElmJson elmJson model.project }
                    , Cmd.none
                    )

                Err _ ->
                    ( model, Cmd.none )

        ReceivedReadme rawReadme ->
            let
                readmeDecoder : Decode.Decoder { path : String, content : String }
                readmeDecoder =
                    Decode.map2 (\path content -> { path = path, content = content })
                        (Decode.field "path" Decode.string)
                        (Decode.field "content" Decode.string)
            in
            case Decode.decodeValue readmeDecoder rawReadme of
                Ok readme ->
                    ( { model | project = Project.addReadme readme model.project }
                    , Cmd.none
                    )

                Err _ ->
                    ( model, Cmd.none )

        ReceivedDependencies json ->
            let
                dependencyDecoder : Decode.Decoder Dependency
                dependencyDecoder =
                    Decode.map3 Dependency.create
                        (Decode.field "name" Decode.string)
                        (Decode.field "elmJson" Elm.Project.decoder)
                        (Decode.field "docsJson" <| Decode.list Elm.Docs.decoder)

                dependenciesDecoder : Decode.Decoder (List Dependency)
                dependenciesDecoder =
                    if model.ignoreProblematicDependencies then
                        Decode.list
                            (Decode.oneOf
                                [ Decode.map Just dependencyDecoder
                                , Decode.succeed Nothing
                                ]
                            )
                            |> Decode.map (List.filterMap identity)

                    else
                        Decode.list dependencyDecoder
            in
            case Decode.decodeValue dependenciesDecoder json of
                Err decodeError ->
                    ( model
                    , if String.contains "I need a valid module name like" (Decode.errorToString decodeError) then
                        abortWithDetails
                            { title = "FOUND PROBLEMATIC DEPENDENCIES"
                            , message =
                                """I encountered an error when reading the dependencies of the project. It seems due to dependencies with modules containing `_` in their names. Unfortunately, this is an error I have no control over and I am waiting in one of the libraries I depend on. What I propose you do, is to re-run elm-review like this:

    elm-review --ignore-problematic-dependencies

This will ignore the problematic dependencies, and can GIVE YOU INCORRECT RESULTS! This is a temporary measure.

If I am mistaken about the nature of problem, please open a bug report at https://github.com/jfmengels/node-elm-review/issues:

"""
                                    ++ Decode.errorToString decodeError
                            }

                      else
                        abortWithDetails
                            { title = "PROBLEM READING DEPENDENCIES"
                            , message =
                                "I encountered an error when reading the dependencies of the project. I suggest opening a bug report at https://github.com/jfmengels/node-elm-review/issues."
                                    ++ Decode.errorToString decodeError
                            }
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

        ReceivedSuppressedErrors json ->
            let
                suppressedErrorsDecoder : Decode.Decoder SuppressedErrorsDict
                suppressedErrorsDecoder =
                    Decode.list suppressedErrorEntryDecoder
                        |> Decode.map (List.concat >> Dict.fromList)

                suppressedErrorEntryDecoder : Decode.Decoder (List ( ( String, String ), Int ))
                suppressedErrorEntryDecoder =
                    Decode.map2
                        (\rule suppressions ->
                            List.map
                                (\( filePath, count ) ->
                                    ( ( rule, filePath ), count )
                                )
                                suppressions
                        )
                        (Decode.field "rule" Decode.string)
                        (Decode.field "suppressions" (Decode.list fileEntryDecoder))

                fileEntryDecoder : Decode.Decoder ( String, Int )
                fileEntryDecoder =
                    Decode.map2 Tuple.pair
                        (Decode.field "filePath" Decode.string)
                        (Decode.field "count" Decode.int)
            in
            case Decode.decodeValue suppressedErrorsDecoder json of
                Err _ ->
                    ( model, Cmd.none )

                Ok suppressedErrors ->
                    ( { model | suppressedErrors = suppressedErrors }, Cmd.none )

        ReceivedLinks json ->
            case Decode.decodeValue (Decode.dict Decode.string) json of
                Err _ ->
                    ( model, Cmd.none )

                Ok links ->
                    ( { model | links = links }, Cmd.none )

        GotRequestToReview ->
            { model
                | project = Project.precomputeModuleGraph model.project
                , fixAllErrors = Dict.empty
            }
                |> runReview
                |> reportOrFix

        GotRequestToGenerateSuppressionErrors ->
            let
                newModel : Model
                newModel =
                    { model
                        | project = Project.precomputeModuleGraph model.project
                        , fixAllErrors = Dict.empty
                    }
                        |> runReview
            in
            ( newModel
            , newModel.reviewErrors
                |> generateSuppressions
                |> encodeSuppressions
                |> suppressionsResponse
            )

        UserConfirmedFix confirmation ->
            case Decode.decodeValue confirmationDecoder confirmation of
                Ok (Accepted rawFiles) ->
                    let
                        newProject : Project
                        newProject =
                            List.foldl addUpdatedFileToProject model.project rawFiles
                    in
                    if List.length (Project.modulesThatFailedToParse newProject) > List.length (Project.modulesThatFailedToParse model.project) then
                        -- There is a new file that failed to parse in the
                        -- project when we updated the fixed file. This means
                        -- that our fix introduced a syntactical regression that
                        -- we were not successful in preventing earlier.
                        ( model
                          -- TODO Improve abort message
                        , abort <| "One file among " ++ (String.join ", " <| List.map .path rawFiles) ++ " could not be read. An incorrect fix may have been introduced into one of these files..."
                        )
                        -- TODO Handle these cases
                        --else if dependenciesHaveChanged then
                        --    ( { model | project = newProject, fixAllErrors = Dict.empty, errorsHaveBeenFixedPreviously = True }
                        --    , abort "The dependencies have changed"
                        --    )
                        --
                        --else if sourceDirectoriesHaveChanged then
                        --    ( { model | project = newProject, fixAllErrors = Dict.empty, errorsHaveBeenFixedPreviously = True }
                        --    , abort "request source directories changed"
                        --    )

                    else
                        { model | project = newProject, fixAllErrors = Dict.empty, errorsHaveBeenFixedPreviously = True }
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
                                -- TODO We should still display the errors that could not be applied here.
                                |> makeReport Dict.empty

                        NotAwaiting ->
                            fixOneByOne model

                Err err ->
                    ( model, abort <| Decode.errorToString err )

        RequestedToKnowIfAFixConfirmationIsExpected ->
            ( model, fixConfirmationStatus (model.errorAwaitingConfirmation /= NotAwaiting) )


elmJsonDecoder : Decode.Decoder { path : String, raw : String, project : Elm.Project.Project }
elmJsonDecoder =
    Decode.map3 (\path raw project -> { path = path, raw = raw, project = project })
        (Decode.field "path" Decode.string)
        (Decode.field "raw" Decode.string)
        (Decode.field "project" Elm.Project.decoder)


cacheFileRequest : Project -> String -> Encode.Value
cacheFileRequest project source =
    case
        project
            |> Project.modules
            |> find (\module_ -> module_.source == source)
    of
        Just { ast } ->
            Encode.object
                [ ( "source", Encode.string source )
                , ( "ast", AstCodec.encode ast )
                ]

        Nothing ->
            Encode.null


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
                , ( "ast", AstCodec.encode ast )
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


refuseError : Rule.ReviewError -> Model -> Model
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
        { errors, rules, projectData } =
            Rule.reviewV2 model.rules model.projectData model.project
    in
    { model
        | reviewErrors = errors
        , reviewErrorsAfterSuppression =
            if Dict.isEmpty model.suppressedErrors then
                errors

            else
                removeSuppressedErrors model.suppressedErrors errors
        , rules = rules
        , projectData = projectData
        , errorAwaitingConfirmation = NotAwaiting
    }


type alias SuppressedErrorsDict =
    Dict ( String, String ) Int


removeSuppressedErrors : SuppressedErrorsDict -> List Rule.ReviewError -> List Rule.ReviewError
removeSuppressedErrors suppressedErrors errors =
    errors
        |> ListExtra.gatherWith (\a b -> (Rule.errorFilePath a == Rule.errorFilePath b) && (Rule.errorRuleName a == Rule.errorRuleName b))
        |> List.concatMap
            (\( head, tail ) ->
                case Dict.get ( Rule.errorRuleName head, Rule.errorFilePath head ) suppressedErrors of
                    Just count ->
                        if List.length tail <= count - 1 then
                            []

                        else
                            head :: tail

                    Nothing ->
                        head :: tail
            )


generateSuppressions : List Rule.ReviewError -> SuppressedErrorsDict
generateSuppressions reviewErrors =
    List.foldl
        (\error acc ->
            Dict.update
                ( Rule.errorRuleName error, Rule.errorFilePath error )
                (Maybe.withDefault 0 >> (+) 1 >> Just)
                acc
        )
        Dict.empty
        reviewErrors


encodeSuppressions : SuppressedErrorsDict -> Encode.Value
encodeSuppressions suppressedErrors =
    suppressedErrors
        |> Dict.toList
        |> List.foldl
            (\( ( ruleName, path ), count ) acc ->
                Dict.update
                    ruleName
                    (Maybe.withDefault [] >> (::) ( count, path ) >> Just)
                    acc
            )
            Dict.empty
        |> Dict.toList
        |> Encode.list
            (\( ruleName, countPerFile ) ->
                encodeRuleSuppression ruleName (encodeFileSuppressions countPerFile)
            )


encodeRuleSuppression : String -> Encode.Value -> Encode.Value
encodeRuleSuppression ruleName fileSuppressions =
    Encode.object
        [ ( "rule", Encode.string ruleName )
        , ( "suppressions", fileSuppressions )
        ]


encodeFileSuppressions : List ( Int, String ) -> Encode.Value
encodeFileSuppressions countPerFile =
    Encode.list encodeFileSuppression countPerFile


encodeFileSuppression : ( Int, String ) -> Encode.Value
encodeFileSuppression ( count, path ) =
    Encode.object
        [ ( "count", Encode.int count )
        , ( "filePath", Encode.string path )
        ]


reportOrFix : Model -> ( Model, Cmd msg )
reportOrFix model =
    case model.fixMode of
        Mode_DontFix ->
            makeReport Dict.empty model

        Mode_Fix ->
            fixOneByOne model

        Mode_FixAll ->
            let
                ( newModel, cmd ) =
                    fixAll model
            in
            ( { newModel | logger = Progress.reset newModel.logger }, cmd )


makeReport : Dict String Fix.Problem -> Model -> ( Model, Cmd msg )
makeReport failedFixesDict model =
    let
        errorsByFile : List { path : Reporter.FilePath, source : Reporter.Source, errors : List Rule.ReviewError }
        errorsByFile =
            groupErrorsByFile model.project model.reviewErrorsAfterSuppression

        suppressedErrors : SuppressedErrorsDict
        suppressedErrors =
            generateSuppressions model.reviewErrors
    in
    ( { model | suppressedErrors = suppressedErrors }
    , [ ( "success", Encode.bool <| List.isEmpty errorsByFile )
      , ( "errors"
        , case model.reportMode of
            HumanReadable ->
                errorsByFile
                    |> List.map
                        (\file ->
                            { path = file.path
                            , source = file.source
                            , errors = List.map (fromReviewError model.links) file.errors
                            }
                        )
                    |> Reporter.formatReport failedFixesDict model.detailsMode model.errorsHaveBeenFixedPreviously
                    |> encodeReport

            Json ->
                Encode.list (encodeErrorByFile model.links model.detailsMode) errorsByFile
        )
      , ( "suppressedErrors", encodeSuppressions suppressedErrors )
      ]
        |> Encode.object
        |> reviewReport
    )


encodeErrorByFile : Dict String String -> Reporter.DetailsMode -> { path : Reporter.FilePath, source : Reporter.Source, errors : List Rule.ReviewError } -> Encode.Value
encodeErrorByFile links detailsMode file =
    Encode.object
        [ ( "path", encodeFilePath file.path )
        , ( "errors", Encode.list (encodeError links detailsMode file.source) file.errors )
        ]


encodeConfigurationErrors : Reporter.DetailsMode -> List Reporter.Error -> Encode.Value
encodeConfigurationErrors detailsMode errors =
    Encode.object
        [ ( "path", encodeFilePath Reporter.ConfigurationError )
        , ( "errors", Encode.list (encodeConfigurationError detailsMode) errors )
        ]


encodeFilePath : Reporter.FilePath -> Encode.Value
encodeFilePath filePath =
    case filePath of
        Reporter.FilePath path ->
            Encode.string path

        Reporter.Global ->
            Encode.null

        Reporter.ConfigurationError ->
            Encode.null


encodeError : Dict String String -> Reporter.DetailsMode -> Reporter.Source -> Rule.ReviewError -> Encode.Value
encodeError links detailsMode source error =
    [ Just ( "rule", Encode.string <| Rule.errorRuleName error )
    , Just ( "message", Encode.string <| Rule.errorMessage error )
    , linkToRule links error
        |> Maybe.map (Encode.string >> Tuple.pair "ruleLink")
    , Just ( "details", Encode.list Encode.string <| Rule.errorDetails error )
    , Just ( "region", encodeRange <| Rule.errorRange error )
    , Rule.errorFixes error
        |> Maybe.map (encodeFixes >> Tuple.pair "fix")
    , Just ( "formatted", encodeReport (Reporter.formatIndividualError Dict.empty detailsMode source (fromReviewError links error)) )
    ]
        |> List.filterMap identity
        |> Encode.object


encodeConfigurationError : Reporter.DetailsMode -> Reporter.Error -> Encode.Value
encodeConfigurationError detailsMode error =
    Encode.object
        [ ( "rule", Encode.string error.ruleName )
        , ( "message", Encode.string error.message )
        , ( "details", Encode.list Encode.string error.details )
        , ( "region", encodeRange Range.emptyRange )
        , ( "formatted", encodeReport (Reporter.formatIndividualError Dict.empty detailsMode (Reporter.Source "") error) )
        ]


linkToRule : Dict String String -> Rule.ReviewError -> Maybe String
linkToRule links error =
    Dict.get (Rule.errorRuleName error) links


encodeFixes : List Fix -> Encode.Value
encodeFixes fixes =
    Encode.list (Fix.toRecord >> encodeFix) fixes


encodeFix : { range : Range, replacement : String } -> Encode.Value
encodeFix { range, replacement } =
    Encode.object
        [ ( "range", encodeRange range )
        , ( "string", Encode.string replacement )
        ]


encodeRange : Range -> Encode.Value
encodeRange range =
    Encode.object
        [ ( "start", encodePosition range.start )
        , ( "end", encodePosition range.end )
        ]


encodePosition : { row : Int, column : Int } -> Encode.Value
encodePosition position =
    Encode.object
        [ ( "line", Encode.int position.row )
        , ( "column", Encode.int position.column )
        ]


fixOneByOne : Model -> ( Model, Cmd msg )
fixOneByOne model =
    case findFix Dict.empty model.refusedErrorFixes (fixableFilesInProject model.project) model.reviewErrorsAfterSuppression |> Tuple.second of
        Just { file, error, fixedSource } ->
            ( { model | errorAwaitingConfirmation = AwaitingError error }
            , [ ( "confirmationMessage"
                , Reporter.formatFixProposal
                    Dict.empty
                    model.detailsMode
                    { path = Reporter.FilePath file.path, source = Reporter.Source file.source }
                    (fromReviewError model.links error)
                    (Reporter.Source fixedSource)
                    |> encodeReport
                )
              , ( "changedFiles"
                , Encode.list encodeChangedFile
                    [ { path = Reporter.FilePath file.path
                      , source = Reporter.Source fixedSource
                      }
                    ]
                )
              , ( "error", Encode.string <| Rule.errorMessage error )
              ]
                |> Encode.object
                |> askConfirmationToFix
            )

        Nothing ->
            makeReport Dict.empty model


fixAll : Model -> ( Model, Cmd msg )
fixAll model =
    case applyAllFixes Dict.empty model of
        Just { failedFixesDict, newModel } ->
            case diff model.project newModel.project of
                [] ->
                    makeReport failedFixesDict newModel

                diffs ->
                    let
                        changedFiles : List { path : Reporter.FilePath, source : Reporter.Source, fixedSource : Reporter.Source, errors : List Reporter.Error }
                        changedFiles =
                            List.map
                                (\{ path, source, fixedSource } ->
                                    { path =
                                        if path == "GLOBAL ERROR" then
                                            Reporter.Global

                                        else
                                            Reporter.FilePath path
                                    , source = Reporter.Source source
                                    , fixedSource = Reporter.Source fixedSource
                                    , errors =
                                        Dict.get path newModel.fixAllErrors
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


encodeChangedFile : { path : Reporter.FilePath, source : Reporter.Source } -> Encode.Value
encodeChangedFile changedFile =
    let
        (Reporter.Source source) =
            changedFile.source
    in
    Encode.object
        [ ( "path", encodeFilePath changedFile.path )
        , ( "source", Encode.string source )
        ]


addUpdatedFileToProject : { a | path : String, source : String } -> Project -> Project
addUpdatedFileToProject file project =
    if Just file.path == (Project.readme project |> Maybe.map .path) then
        Project.addReadme { path = file.path, content = file.source } project

    else
        case Project.elmJson project of
            Just oldElmJson ->
                if file.path == oldElmJson.path then
                    case Decode.decodeString Elm.Project.decoder file.source of
                        Ok newElmJson ->
                            List.foldl
                                Project.removeDependency
                                (Project.addElmJson { path = file.path, raw = file.source, project = newElmJson } project)
                                (removedDependencies oldElmJson.project newElmJson)

                        Err _ ->
                            -- TODO Error
                            project

                else
                    addElmFile file project

            Nothing ->
                addElmFile file project


removedDependencies : Elm.Project.Project -> Elm.Project.Project -> List String
removedDependencies old new =
    Set.diff (projectDependencies old) (projectDependencies new)
        |> Set.toList


projectDependencies : Elm.Project.Project -> Set String
projectDependencies project =
    case project of
        Elm.Project.Application application ->
            List.concat
                [ getPackageName application.depsDirect
                , getPackageName application.depsIndirect
                , getPackageName application.testDepsDirect
                , getPackageName application.testDepsIndirect
                ]
                |> Set.fromList

        Elm.Project.Package packageInfo ->
            List.concat
                [ getPackageName packageInfo.deps
                , getPackageName packageInfo.testDeps
                ]
                |> Set.fromList


getPackageName : Elm.Project.Deps a -> List String
getPackageName deps =
    List.map (Tuple.first >> Elm.Package.toString) deps


addElmFile : { a | path : String, source : String } -> Project -> Project
addElmFile file project =
    Project.addModule { path = file.path, source = file.source } project


applyAllFixes : Dict String Fix.Problem -> Model -> Maybe { failedFixesDict : Dict String Fix.Problem, newModel : Model }
applyAllFixes failedFixesDict model =
    case findFix failedFixesDict model.refusedErrorFixes (fixableFilesInProject model.project) model.reviewErrorsAfterSuppression of
        ( newFailedFixesDict, Just { file, error, fixedSource, remainingErrors } ) ->
            let
                newProject : Project
                newProject =
                    addUpdatedFileToProject { file | source = fixedSource } model.project
            in
            if List.length (Project.modulesThatFailedToParse newProject) > List.length (Project.modulesThatFailedToParse model.project) then
                -- There is a new module that failed to parse in the
                -- project when we updated the fixed file. This means
                -- that our fix introduced a syntactical regression that
                -- we were not successful in preventing earlier.
                Nothing

            else if not <| List.isEmpty (changesToElm model.project newProject) then
                Just
                    { failedFixesDict = newFailedFixesDict
                    , newModel =
                        addFixedErrorForFile
                            file.path
                            error
                            remainingErrors
                            { model | project = newProject }
                    }

            else
                applyAllFixes
                    newFailedFixesDict
                    ({ model | project = newProject }
                        |> addFixedErrorForFile file.path error remainingErrors
                        |> runReview
                    )

        ( newFailedFixesDict, Nothing ) ->
            Just
                { failedFixesDict = newFailedFixesDict
                , newModel = model
                }


type ElmJsonChange
    = SourceDirectoriesChanged
    | DependenciesChanged


changesToElm : Project -> Project -> List ElmJsonChange
changesToElm oldProject newProject =
    case Maybe.map2 Tuple.pair (Project.elmJson oldProject) (Project.elmJson newProject) of
        Just ( oldElmJson, newElmJson ) ->
            if oldElmJson == newElmJson then
                []

            else
                case ( oldElmJson.project, newElmJson.project ) of
                    ( Elm.Project.Application oldApp, Elm.Project.Application newApp ) ->
                        List.filterMap identity
                            [ if Set.fromList oldApp.dirs == Set.fromList newApp.dirs then
                                Nothing

                              else
                                Just SourceDirectoriesChanged
                            , if normalizeApplicationDeps oldApp == normalizeApplicationDeps newApp then
                                Nothing

                              else
                                Just DependenciesChanged
                            ]

                    ( Elm.Project.Package oldPackage, Elm.Project.Package newPackage ) ->
                        List.filterMap identity
                            [ if normalizePackageDeps oldPackage == normalizePackageDeps newPackage then
                                Nothing

                              else
                                Just DependenciesChanged
                            ]

                    _ ->
                        [ SourceDirectoriesChanged, DependenciesChanged ]

        Nothing ->
            []


normalizeApplicationDeps : Elm.Project.ApplicationInfo -> List (Dict String Elm.Version.Version)
normalizeApplicationDeps application =
    [ List.map (\( name, version ) -> ( Elm.Package.toString name, version )) application.depsDirect |> Dict.fromList
    , List.map (\( name, version ) -> ( Elm.Package.toString name, version )) application.depsIndirect |> Dict.fromList
    , List.map (\( name, version ) -> ( Elm.Package.toString name, version )) application.testDepsDirect |> Dict.fromList
    , List.map (\( name, version ) -> ( Elm.Package.toString name, version )) application.testDepsIndirect |> Dict.fromList
    ]


normalizePackageDeps : Elm.Project.PackageInfo -> List (Dict String Elm.Constraint.Constraint)
normalizePackageDeps application =
    [ List.map (\( name, constraint ) -> ( Elm.Package.toString name, constraint )) application.deps |> Dict.fromList
    , List.map (\( name, constraint ) -> ( Elm.Package.toString name, constraint )) application.testDeps |> Dict.fromList
    ]


addFixedErrorForFile : String -> Rule.ReviewError -> List Rule.ReviewError -> Model -> Model
addFixedErrorForFile path error remainingErrors model =
    let
        errorsForFile : List Reporter.Error
        errorsForFile =
            fromReviewError model.links error
                :: (Dict.get path model.fixAllErrors
                        |> Maybe.withDefault []
                   )
    in
    { model
        | fixAllErrors = Dict.insert path errorsForFile model.fixAllErrors
        , logger = Progress.fixWasApplied remainingErrors model.logger
    }


fixableFilesInProject : Project -> Dict String { path : String, source : String }
fixableFilesInProject project =
    let
        elmJson : { path : String, source : String }
        elmJson =
            Project.elmJson project
                |> Maybe.map (\r -> { path = r.path, source = r.raw })
                |> Maybe.withDefault { path = "$$Not a valid module name$$", source = "" }

        readme : { path : String, source : String }
        readme =
            Project.readme project
                |> Maybe.map (\r -> { path = r.path, source = r.content })
                |> Maybe.withDefault { path = "$$Not a valid module name$$", source = "" }

        moduleFiles : List ( String, { path : String, source : String } )
        moduleFiles =
            Project.modules project
                |> List.map (\module_ -> ( module_.path, { path = module_.path, source = module_.source } ))
    in
    Dict.fromList (( elmJson.path, elmJson ) :: ( readme.path, readme ) :: moduleFiles)


findFix :
    Dict String Fix.Problem
    -> RefusedErrorFixes
    -> Dict String { path : String, source : String }
    -> List Rule.ReviewError
    ->
        ( Dict String Fix.Problem
        , Maybe
            { file : { path : String, source : String }
            , error : Rule.ReviewError
            , fixedSource : String
            , remainingErrors : List Rule.ReviewError
            }
        )
findFix failedFixesDict refusedErrorFixes files errors =
    case errors of
        [] ->
            ( failedFixesDict, Nothing )

        error :: restOfErrors ->
            if RefusedErrorFixes.member error refusedErrorFixes then
                findFix failedFixesDict refusedErrorFixes files restOfErrors

            else
                case Rule.errorFixes error of
                    Just fixes ->
                        case Dict.get (Rule.errorFilePath error) files of
                            Nothing ->
                                findFix failedFixesDict refusedErrorFixes files restOfErrors

                            Just file ->
                                case Fix.fix (Rule.errorTarget error) fixes file.source of
                                    Fix.Errored problem ->
                                        -- Ignore error if applying the fix results in a problem
                                        findFix
                                            (Dict.insert (Reporter.hashFixes fixes) problem failedFixesDict)
                                            refusedErrorFixes
                                            files
                                            restOfErrors

                                    Fix.Successful fixedSource ->
                                        -- Return error and the result of the fix otherwise
                                        ( failedFixesDict
                                        , Just
                                            { file = { path = file.path, source = file.source }
                                            , error = error
                                            , fixedSource = fixedSource
                                            , remainingErrors = restOfErrors
                                            }
                                        )

                    Nothing ->
                        findFix failedFixesDict refusedErrorFixes files restOfErrors


type alias FixedFile =
    { path : String
    , source : String
    , fixedSource : String
    }


diff : Project -> Project -> List FixedFile
diff before after =
    let
        beforeReadme : List ( String, { path : String, source : String } )
        beforeReadme =
            case Project.readme before of
                Just readme ->
                    [ ( readme.path, { path = readme.path, source = readme.content } ) ]

                Nothing ->
                    []

        afterReadme : List ( String, String )
        afterReadme =
            case Project.readme after of
                Just readme ->
                    [ ( readme.path, readme.content ) ]

                Nothing ->
                    []

        beforeElmJson : List ( String, { path : String, source : String } )
        beforeElmJson =
            case Project.elmJson before of
                Just readme ->
                    [ ( readme.path, { path = readme.path, source = readme.raw } ) ]

                Nothing ->
                    []

        afterElmJson : List ( String, String )
        afterElmJson =
            case Project.elmJson after of
                Just elmJson ->
                    [ ( elmJson.path, elmJson.raw ) ]

                Nothing ->
                    []

        beforeModules : Dict String { path : String, source : String }
        beforeModules =
            List.concat
                [ beforeReadme
                , beforeElmJson
                , before
                    |> Project.modules
                    |> List.map (\mod -> ( mod.path, { path = mod.path, source = mod.source } ))
                ]
                |> Dict.fromList

        fixedSources : Dict String String
        fixedSources =
            List.concat
                [ afterReadme
                , afterElmJson
                , after
                    |> Project.modules
                    |> List.map (\mod -> ( mod.path, mod.source ))
                ]
                |> Dict.fromList
    in
    Dict.merge
        (\_ _ acc -> acc)
        (\_ beforeModule fixedSource acc ->
            if beforeModule.source /= fixedSource then
                { path = beforeModule.path, source = beforeModule.source, fixedSource = fixedSource } :: acc

            else
                acc
        )
        (\_ _ acc -> acc)
        beforeModules
        fixedSources
        []


groupErrorsByFile : Project -> List Rule.ReviewError -> List { path : Reporter.FilePath, source : Reporter.Source, errors : List Rule.ReviewError }
groupErrorsByFile project errors =
    let
        files : List { path : String, source : String }
        files =
            List.concat
                [ project
                    |> Project.modules
                    |> List.map (\file -> { path = file.path, source = file.source })
                , [ { path = "GLOBAL ERROR", source = "" }
                  , { path = "CONFIGURATION ERROR", source = "" }
                  ]
                , case Project.elmJson project of
                    Just { path, raw } ->
                        [ { path = path, source = raw } ]

                    Nothing ->
                        []
                , case Project.readme project of
                    Just { path, content } ->
                        [ { path = path, source = content } ]

                    Nothing ->
                        []
                , Project.modulesThatFailedToParse project
                ]
    in
    files
        |> List.map
            (\file ->
                { path =
                    if file.path == "GLOBAL ERROR" then
                        Reporter.Global

                    else if file.path == "CONFIGURATION ERROR" then
                        Reporter.ConfigurationError

                    else
                        Reporter.FilePath file.path
                , source = Reporter.Source file.source
                , errors = List.filter (\error -> file.path == Rule.errorFilePath error) errors
                }
            )
        |> List.filter (\file -> not (List.isEmpty file.errors))


fromReviewError : Dict String String -> Rule.ReviewError -> Reporter.Error
fromReviewError links error =
    { ruleName = Rule.errorRuleName error
    , ruleLink = linkToRule links error
    , message = Rule.errorMessage error
    , details = Rule.errorDetails error
    , range = Rule.errorRange error
    , fixesHash = Maybe.map Reporter.hashFixes (Rule.errorFixes error)
    }



-- ENCODING


{-| Encode texts to a JSON value.
-}
encodeReport : List Reporter.TextContent -> Encode.Value
encodeReport texts =
    Encode.list encodeReportPart texts


encodeReportPart : Reporter.TextContent -> Encode.Value
encodeReportPart { str, color, href } =
    if color == Nothing && href == Nothing then
        Encode.string str

    else
        [ Just ( "string", Encode.string str )
        , Maybe.map (Encode.string >> Tuple.pair "color") color
        , Maybe.map (Encode.string >> Tuple.pair "href") href
        ]
            |> List.filterMap identity
            |> Encode.object



-- REVIEWING


subscriptions : Sub Msg
subscriptions =
    Sub.batch
        [ collectFile ReceivedFile
        , removeFile RemovedFile
        , collectElmJson ReceivedElmJson
        , collectReadme ReceivedReadme
        , collectDependencies ReceivedDependencies
        , collectSuppressedErrors ReceivedSuppressedErrors
        , collectLinks ReceivedLinks
        , startReview (always GotRequestToReview)
        , startGeneratingSuppressions (always GotRequestToGenerateSuppressionErrors)
        , userConfirmedFix UserConfirmedFix
        , askForFixConfirmationStatus (always RequestedToKnowIfAFixConfirmationIsExpected)
        ]

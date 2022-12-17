port module Elm.Review.Main exposing (main)

import Dict exposing (Dict)
import Elm.Constraint
import Elm.Docs
import Elm.Package
import Elm.Project
import Elm.Review.AstCodec as AstCodec
import Elm.Review.CliCommunication as CliCommunication
import Elm.Review.File
import Elm.Review.RefusedErrorFixes as RefusedErrorFixes exposing (RefusedErrorFixes)
import Elm.Review.Reporter as Reporter
import Elm.Review.SuppressedErrors as SuppressedErrors exposing (SuppressedErrors)
import Elm.Review.UnsuppressMode as UnsuppressMode exposing (UnsuppressMode)
import Elm.Review.Vendor.Levenshtein as Levenshtein
import Elm.Syntax.File
import Elm.Syntax.Range as Range exposing (Range)
import Elm.Version
import Json.Decode as Decode
import Json.Encode as Encode
import Review.Fix as Fix exposing (Fix)
import Review.Options as ReviewOptions
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


port updateSuppressedErrors : (Decode.Value -> msg) -> Sub msg


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
    , fixAllRules : List Rule
    , project : Project
    , isInitialRun : Bool
    , links : Dict String String
    , fixMode : FixMode
    , fixLimit : Maybe Int
    , enableExtract : Bool
    , unsuppressMode : UnsuppressMode
    , detailsMode : Reporter.DetailsMode
    , reportMode : ReportMode
    , reviewErrors : List Rule.ReviewError
    , reviewErrorsAfterSuppression : List Rule.ReviewError
    , suppressedErrors : SuppressedErrors
    , originalNumberOfSuppressedErrors : Int
    , writeSuppressionFiles : Bool
    , errorsHaveBeenFixedPreviously : Bool
    , extracts : Dict String Encode.Value
    , ignoreProblematicDependencies : Bool

    -- FIX
    , refusedErrorFixes : RefusedErrorFixes
    , errorAwaitingConfirmation : AwaitingConfirmation

    -- FIX ALL
    , fixAllResultProject : Project
    , fixAllErrors : Dict String (List Rule.ReviewError)
    , communicationKey : CliCommunication.Key
    }


type AwaitingConfirmation
    = NotAwaiting
    | AwaitingError Rule.ReviewError
    | AwaitingFixAll


type FixMode
    = Mode_DontFix
    | Mode_Fix
    | Mode_FixAll


toReviewOptionsFixMode : Bool -> Model -> ReviewOptions.FixMode
toReviewOptionsFixMode fixAllAllowed model =
    if not fixAllAllowed then
        ReviewOptions.fixedDisabled

    else
        case model.fixMode of
            Mode_DontFix ->
                ReviewOptions.fixedDisabled

            Mode_Fix ->
                case model.fixLimit of
                    Just fixLimit ->
                        ReviewOptions.fixesEnabledWithLimit fixLimit

                    Nothing ->
                        ReviewOptions.fixesEnabledWithLimit 1

            Mode_FixAll ->
                case model.fixLimit of
                    Just fixLimit ->
                        ReviewOptions.fixesEnabledWithLimit fixLimit

                    Nothing ->
                        ReviewOptions.fixesEnabledWithoutLimits


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
                      , fixLimit = Nothing
                      , enableExtract = False
                      , unsuppressMode = UnsuppressMode.UnsuppressNone
                      , reportMode = HumanReadable
                      , detailsMode = Reporter.WithoutDetails
                      , ignoreProblematicDependencies = False
                      , rulesFilter = Nothing
                      , ignoredDirs = []
                      , ignoredFiles = []
                      , writeSuppressionFiles = False
                      , logger = CliCommunication.dummy
                      }
                    , abort <| "Problem decoding the flags when running the elm-review runner:\n  " ++ Decode.errorToString error
                    )

        rulesWithIds : List Rule
        rulesWithIds =
            List.indexedMap Rule.withRuleId config

        ( rulesFromConfig, filterNames ) =
            case flags.rulesFilter of
                Just rulesToEnable ->
                    let
                        ruleNames : Set String
                        ruleNames =
                            List.map Rule.ruleName rulesWithIds
                                |> Set.fromList
                    in
                    ( List.filter (\rule -> Set.member (Rule.ruleName rule) rulesToEnable) rulesWithIds
                    , Set.diff rulesToEnable ruleNames
                        |> Set.toList
                    )

                Nothing ->
                    ( rulesWithIds, [] )

        rules : List Rule
        rules =
            List.map
                (Rule.ignoreErrorsForDirectories flags.ignoredDirs >> Rule.ignoreErrorsForFiles flags.ignoredFiles)
                rulesFromConfig
    in
    ( { rules = rules
      , fixAllRules = rules
      , project = Project.new
      , isInitialRun = True
      , links = Dict.empty
      , fixAllResultProject = Project.new
      , fixMode = flags.fixMode
      , fixLimit = flags.fixLimit
      , enableExtract = flags.enableExtract
      , unsuppressMode = flags.unsuppressMode
      , detailsMode = flags.detailsMode
      , reportMode = flags.reportMode
      , reviewErrors = []
      , reviewErrorsAfterSuppression = []
      , suppressedErrors = SuppressedErrors.empty
      , originalNumberOfSuppressedErrors = 0
      , writeSuppressionFiles = flags.writeSuppressionFiles
      , errorsHaveBeenFixedPreviously = False
      , refusedErrorFixes = RefusedErrorFixes.empty
      , errorAwaitingConfirmation = NotAwaiting
      , fixAllErrors = Dict.empty
      , ignoreProblematicDependencies = flags.ignoreProblematicDependencies
      , extracts = Dict.empty
      , communicationKey = flags.logger
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
                            Reporter.formatReport
                                { suppressedErrors = SuppressedErrors.empty
                                , unsuppressMode = flags.unsuppressMode
                                , originalNumberOfSuppressedErrors = 0
                                , detailsMode = flags.detailsMode
                                , errorsHaveBeenFixedPreviously = False
                                , fixProblemDict = Dict.empty
                                }
                                [ { path = Reporter.ConfigurationError
                                  , source = Reporter.Source ""
                                  , errors = configurationErrors
                                  }
                                ]
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
                , suppressed = False
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
    , fixLimit : Maybe Int
    , enableExtract : Bool
    , unsuppressMode : UnsuppressMode
    , detailsMode : Reporter.DetailsMode
    , reportMode : ReportMode
    , ignoreProblematicDependencies : Bool
    , rulesFilter : Maybe (Set String)
    , ignoredDirs : List String
    , ignoredFiles : List String
    , writeSuppressionFiles : Bool
    , logger : CliCommunication.Key
    }


decodeFlags : Decode.Decoder DecodedFlags
decodeFlags =
    Decode.succeed DecodedFlags
        |> field "fixMode" decodeFix
        |> field "fixLimit" decodeFixLimit
        |> field "enableExtract" Decode.bool
        |> field "unsuppress" UnsuppressMode.decoder
        |> field "detailsMode" decodeDetailsMode
        |> field "report" decodeReportMode
        |> field "ignoreProblematicDependencies" Decode.bool
        |> field "rulesFilter" decodeRulesFilter
        |> field "ignoredDirs" (Decode.list Decode.string)
        |> field "ignoredFiles" (Decode.list Decode.string)
        |> field "writeSuppressionFiles" Decode.bool
        |> field "logger" CliCommunication.decoder


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


decodeFixLimit : Decode.Decoder (Maybe Int)
decodeFixLimit =
    Decode.oneOf
        [ Decode.int
            |> Decode.map (\n -> Just (max 1 n))
        , Decode.null Nothing
        ]


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
    | UpdateSuppressedErrors Decode.Value
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
            case Decode.decodeValue SuppressedErrors.decoder json of
                Err _ ->
                    -- TODO Report something?
                    -- TODO Report if version is not supported
                    ( model, Cmd.none )

                Ok suppressedErrors ->
                    ( { model
                        | suppressedErrors = suppressedErrors
                        , originalNumberOfSuppressedErrors = SuppressedErrors.count suppressedErrors
                      }
                    , Cmd.none
                    )

        UpdateSuppressedErrors json ->
            case Decode.decodeValue SuppressedErrors.decoder json of
                Err _ ->
                    -- TODO Report something?
                    -- TODO Report if version is not supported
                    ( model, Cmd.none )

                Ok suppressedErrors ->
                    if suppressedErrors == model.suppressedErrors then
                        ( model, Cmd.none )

                    else
                        makeReport Dict.empty
                            { model
                                | suppressedErrors = suppressedErrors
                                , reviewErrorsAfterSuppression = SuppressedErrors.apply model.unsuppressMode suppressedErrors model.reviewErrors
                            }

        ReceivedLinks json ->
            case Decode.decodeValue (Decode.dict Decode.string) json of
                Err _ ->
                    ( model, Cmd.none )

                Ok links ->
                    ( { model | links = links }, Cmd.none )

        GotRequestToReview ->
            { model | fixAllErrors = Dict.empty }
                |> runReview { fixesAllowed = True } model.project
                |> reportOrFix

        GotRequestToGenerateSuppressionErrors ->
            let
                project : Project
                project =
                    Project.precomputeModuleGraph model.project

                newModel : Model
                newModel =
                    { model
                        | project = project
                        , fixAllErrors = Dict.empty
                    }
                        |> runReview { fixesAllowed = False } project
            in
            ( newModel
            , newModel.reviewErrors
                |> SuppressedErrors.fromReviewErrors
                |> SuppressedErrors.encode []
                |> suppressionsResponse
            )

        UserConfirmedFix confirmation ->
            case Decode.decodeValue confirmationDecoder confirmation of
                Ok (Accepted rawFiles) ->
                    let
                        previousProject : Project
                        previousProject =
                            model.fixAllResultProject

                        newProject : Project
                        newProject =
                            List.foldl addUpdatedFileToProject previousProject rawFiles
                    in
                    if List.length (Project.modulesThatFailedToParse newProject) > List.length (Project.modulesThatFailedToParse previousProject) then
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
                        { model
                            | project = newProject
                            , rules = model.fixAllRules
                            , fixAllErrors = Dict.empty
                            , errorsHaveBeenFixedPreviously = True
                        }
                            |> runReview { fixesAllowed = True } newProject
                            |> reportOrFix
                            -- TODO Separate sending files to be cached and computing the files.
                            -- We may now already have found new fixes which are likely to be accepted.
                            |> Tuple.mapSecond
                                (\cmd ->
                                    (cmd :: List.map (.source >> sendFileToBeCached newProject) rawFiles)
                                        |> Cmd.batch
                                )

                Ok Refused ->
                    case model.errorAwaitingConfirmation of
                        AwaitingError error ->
                            { model
                                | errorAwaitingConfirmation = NotAwaiting
                                , fixAllResultProject = model.project
                            }
                                |> refuseError error
                                |> runReview { fixesAllowed = True } model.project
                                |> reportOrFix

                        AwaitingFixAll ->
                            { model
                                | errorAwaitingConfirmation = NotAwaiting
                                , fixAllResultProject = model.project
                            }
                                |> runReview { fixesAllowed = False } model.project
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


runReview : { fixesAllowed : Bool } -> Project -> Model -> Model
runReview { fixesAllowed } initialProject model =
    let
        { errors, rules, project, extracts, fixedErrors } =
            initialProject
                |> CliCommunication.timerStart model.communicationKey "run-review"
                |> Rule.reviewV3
                    (ReviewOptions.defaults
                        |> ReviewOptions.withDataExtraction (model.enableExtract && model.reportMode == Json)
                        |> ReviewOptions.withLogger (Just (CliCommunication.send model.communicationKey))
                        |> ReviewOptions.withFixes (toReviewOptionsFixMode fixesAllowed model)
                        |> ReviewOptions.withIgnoredFixes (\error -> RefusedErrorFixes.memberUsingRecord error model.refusedErrorFixes)
                        |> SuppressedErrors.addToReviewOptions model.suppressedErrors
                    )
                    model.rules
                |> CliCommunication.timerEnd model.communicationKey "run-review"
    in
    { model
        | reviewErrors = errors
        , reviewErrorsAfterSuppression =
            errors
                |> CliCommunication.timerStart model.communicationKey "apply-suppressions"
                |> SuppressedErrors.apply model.unsuppressMode model.suppressedErrors
                |> CliCommunication.timerEnd model.communicationKey "apply-suppressions"
        , rules =
            if model.isInitialRun || model.fixMode == Mode_DontFix then
                rules

            else
                model.rules
        , isInitialRun = False
        , fixAllRules = rules
        , project =
            if model.fixMode == Mode_DontFix then
                project

            else
                model.project
        , fixAllResultProject = project
        , fixAllErrors = fixedErrors
        , errorAwaitingConfirmation = NotAwaiting
        , extracts = extracts
    }


reportOrFix : Model -> ( Model, Cmd msg )
reportOrFix model =
    case model.fixMode of
        Mode_DontFix ->
            model
                |> CliCommunication.timerStart model.communicationKey "process-errors"
                |> makeReport Dict.empty
                |> CliCommunication.timerEnd model.communicationKey "process-errors"

        Mode_Fix ->
            applyFixesAfterReview model True

        Mode_FixAll ->
            applyFixesAfterReview model False


makeReport : Dict String Fix.Problem -> Model -> ( Model, Cmd msg )
makeReport failedFixesDict model =
    let
        ( newModel, suppressedErrorsForJson ) =
            if List.isEmpty model.reviewErrorsAfterSuppression && model.writeSuppressionFiles then
                let
                    suppressedErrors : SuppressedErrors
                    suppressedErrors =
                        SuppressedErrors.fromReviewErrors model.reviewErrors
                in
                ( { model | suppressedErrors = suppressedErrors, rules = model.fixAllRules }
                , SuppressedErrors.encode (List.map Rule.ruleName model.rules) suppressedErrors
                )

            else
                ( { model | rules = model.fixAllRules }, Encode.null )
    in
    ( newModel
    , [ ( "success", Encode.bool <| List.isEmpty model.reviewErrorsAfterSuppression )
      , ( "errors"
        , case newModel.reportMode of
            HumanReadable ->
                let
                    errorsByFile : List { path : Reporter.FilePath, source : Reporter.Source, errors : List Rule.ReviewError }
                    errorsByFile =
                        groupErrorsByFile model.project model.reviewErrorsAfterSuppression

                    filesWithError : List { path : Reporter.FilePath, source : Reporter.Source, errors : List Reporter.Error }
                    filesWithError =
                        List.map
                            (\file ->
                                { path = file.path
                                , source = file.source
                                , errors = List.map (fromReviewError newModel.suppressedErrors newModel.links) file.errors
                                }
                            )
                            errorsByFile
                in
                Reporter.formatReport
                    { suppressedErrors = newModel.suppressedErrors
                    , unsuppressMode = newModel.unsuppressMode
                    , originalNumberOfSuppressedErrors = newModel.originalNumberOfSuppressedErrors
                    , detailsMode = newModel.detailsMode
                    , errorsHaveBeenFixedPreviously = newModel.errorsHaveBeenFixedPreviously
                    , fixProblemDict = failedFixesDict
                    }
                    filesWithError
                    |> encodeReport

            Json ->
                let
                    errorsByFile : List { path : Reporter.FilePath, source : Reporter.Source, errors : List Rule.ReviewError }
                    errorsByFile =
                        groupErrorsByFile model.project model.reviewErrors
                in
                Encode.list
                    (encodeErrorByFile
                        { suppressedErrors = newModel.suppressedErrors
                        , reviewErrorsAfterSuppression = model.reviewErrorsAfterSuppression
                        }
                        newModel.links
                        newModel.detailsMode
                    )
                    errorsByFile
        )
      , ( "extracts", Encode.dict identity identity newModel.extracts )
      , ( "suppressedErrors", suppressedErrorsForJson )
      ]
        |> Encode.object
        |> reviewReport
    )


encodeErrorByFile :
    { suppressedErrors : SuppressedErrors
    , reviewErrorsAfterSuppression : List Rule.ReviewError
    }
    -> Dict String String
    -> Reporter.DetailsMode
    -> { path : Reporter.FilePath, source : Reporter.Source, errors : List Rule.ReviewError }
    -> Encode.Value
encodeErrorByFile suppressedErrorsData links detailsMode file =
    Encode.object
        [ ( "path", encodeFilePath file.path )
        , ( "errors", Encode.list (encodeError suppressedErrorsData links detailsMode file.source) file.errors )
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


encodeError :
    { suppressedErrors : SuppressedErrors
    , reviewErrorsAfterSuppression : List Rule.ReviewError
    }
    -> Dict String String
    -> Reporter.DetailsMode
    -> Reporter.Source
    -> Rule.ReviewError
    -> Encode.Value
encodeError { suppressedErrors, reviewErrorsAfterSuppression } links detailsMode source error =
    let
        originallySuppressed : Bool
        originallySuppressed =
            SuppressedErrors.member error suppressedErrors
    in
    [ Just ( "rule", Encode.string <| Rule.errorRuleName error )
    , Just ( "message", Encode.string <| Rule.errorMessage error )
    , linkToRule links error
        |> Maybe.map (Encode.string >> Tuple.pair "ruleLink")
    , Just ( "details", Encode.list Encode.string <| Rule.errorDetails error )
    , Just ( "region", encodeRange <| Rule.errorRange error )
    , Rule.errorFixes error
        |> Maybe.map (encodeFixes >> Tuple.pair "fix")
    , Just ( "formatted", encodeReport (Reporter.formatIndividualError Dict.empty detailsMode source (fromReviewError suppressedErrors links error)) )
    , Just ( "suppressed", Encode.bool (originallySuppressed && not (List.member error reviewErrorsAfterSuppression)) )
    , Just ( "originallySuppressed", Encode.bool originallySuppressed )
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
                    model.detailsMode
                    { path = Reporter.FilePath file.path, source = Reporter.Source file.source }
                    (fromReviewError model.suppressedErrors model.links error)
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
              , ( "count", Encode.int 1 )
              ]
                |> Encode.object
                |> askConfirmationToFix
            )

        Nothing ->
            makeReport Dict.empty model


applyFixesAfterReview : Model -> Bool -> ( Model, Cmd msg )
applyFixesAfterReview model allowPrintingSingleFix =
    case applyAllFixes Dict.empty model of
        Just { failedFixesDict, newModel } ->
            case diff model.project newModel.fixAllResultProject of
                [] ->
                    makeReport failedFixesDict newModel

                diffs ->
                    let
                        modelWithOldProject : Model
                        modelWithOldProject =
                            { newModel | project = model.project }
                    in
                    if allowPrintingSingleFix then
                        sendFixPrompt modelWithOldProject diffs

                    else
                        ( { modelWithOldProject | errorAwaitingConfirmation = AwaitingFixAll }
                        , sendFixPromptForMultipleFixes modelWithOldProject diffs (countErrors modelWithOldProject.fixAllErrors)
                        )

        Nothing ->
            ( model
            , abort "Got an error while trying to fix all automatic fixes. One of them made the code invalid. I suggest fixing the errors manually, or using `--fix` but with a lot of precaution."
            )


sendFixPrompt : Model -> List FixedFile -> ( Model, Cmd msg )
sendFixPrompt model diffs =
    case numberOfErrors model.fixAllErrors of
        NoErrors ->
            ( model, Cmd.none )

        OneError filePath error ->
            case find (\diff_ -> diff_.path == filePath) diffs of
                Just { source, fixedSource } ->
                    ( { model | errorAwaitingConfirmation = AwaitingError error }
                    , [ ( "confirmationMessage"
                        , Reporter.formatFixProposal
                            model.detailsMode
                            { path = Reporter.FilePath filePath, source = Reporter.Source source }
                            (fromReviewError model.suppressedErrors model.links error)
                            (Reporter.Source fixedSource)
                            |> encodeReport
                        )
                      , ( "changedFiles"
                        , Encode.list encodeChangedFile
                            [ { path = Reporter.FilePath filePath
                              , source = Reporter.Source fixedSource
                              }
                            ]
                        )
                      , ( "count", Encode.int 1 )
                      ]
                        |> Encode.object
                        |> askConfirmationToFix
                    )

                Nothing ->
                    -- Should not happen
                    ( model, Cmd.none )

        MultipleErrors numberOfFixedErrors ->
            ( { model | errorAwaitingConfirmation = AwaitingFixAll }, sendFixPromptForMultipleFixes model diffs numberOfFixedErrors )


sendFixPromptForMultipleFixes : Model -> List FixedFile -> Int -> Cmd msg
sendFixPromptForMultipleFixes model diffs numberOfFixedErrors =
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
                        Dict.get path model.fixAllErrors
                            |> Maybe.withDefault []
                            |> List.map (fromReviewError model.suppressedErrors model.links)
                    }
                )
                diffs

        confirmationMessage : Encode.Value
        confirmationMessage =
            changedFiles
                |> Reporter.formatFixProposals
                |> encodeReport
    in
    askConfirmationToFix
        (Encode.object
            [ ( "confirmationMessage", confirmationMessage )
            , ( "changedFiles"
              , changedFiles
                    |> List.map (\file -> { path = file.path, source = file.fixedSource })
                    |> Encode.list encodeChangedFile
              )
            , ( "count", Encode.int numberOfFixedErrors )
            , ( "clearFixLine", Encode.bool (model.fixMode == Mode_FixAll) )
            ]
        )


countErrors : Dict String (List a) -> Int
countErrors dict =
    Dict.foldl (\_ errors count -> List.length errors + count) 0 dict


type NumberOfErrors
    = NoErrors
    | OneError String Rule.ReviewError
    | MultipleErrors Int


numberOfErrors : Dict String (List Rule.ReviewError) -> NumberOfErrors
numberOfErrors dict =
    case Dict.toList dict of
        [] ->
            NoErrors

        [ ( filePath, [ singleError ] ) ] ->
            OneError filePath singleError

        list ->
            MultipleErrors (List.length list)


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
    case findFix failedFixesDict model.refusedErrorFixes (fixableFilesInProject model.fixAllResultProject) model.reviewErrorsAfterSuppression of
        ( newFailedFixesDict, Just { file, error, fixedSource } ) ->
            let
                newProject : Project
                newProject =
                    addUpdatedFileToProject { file | source = fixedSource } model.fixAllResultProject
            in
            if List.length (Project.modulesThatFailedToParse newProject) > List.length (Project.modulesThatFailedToParse model.fixAllResultProject) then
                -- There is a new module that failed to parse in the
                -- project when we updated the fixed file. This means
                -- that our fix introduced a syntactical regression that
                -- we were not successful in preventing earlier.
                Nothing

            else if not <| List.isEmpty (changesToElm model.fixAllResultProject newProject) then
                Just
                    { failedFixesDict = newFailedFixesDict
                    , newModel =
                        addFixedErrorForFile
                            file.path
                            error
                            { model | fixAllResultProject = newProject }
                    }

            else
                applyAllFixes
                    newFailedFixesDict
                    ({ model | fixAllResultProject = newProject }
                        |> addFixedErrorForFile file.path error
                        |> runReview { fixesAllowed = True } newProject
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


addFixedErrorForFile : String -> Rule.ReviewError -> Model -> Model
addFixedErrorForFile path error model =
    let
        errorsForFile : List Rule.ReviewError
        errorsForFile =
            CliCommunication.appliedFix model.communicationKey (countErrors model.fixAllErrors) error
                :: (Dict.get path model.fixAllErrors
                        |> Maybe.withDefault []
                   )
    in
    { model | fixAllErrors = Dict.insert path errorsForFile model.fixAllErrors }


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
            }
        )
findFix failedFixesDict refusedErrorFixes files errors =
    case errors of
        [] ->
            ( failedFixesDict, Nothing )

        error :: restOfErrors ->
            case Rule.errorFixes error of
                Just fixes ->
                    if RefusedErrorFixes.member error refusedErrorFixes then
                        findFix failedFixesDict refusedErrorFixes files restOfErrors

                    else
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


fromReviewError : SuppressedErrors -> Dict String String -> Rule.ReviewError -> Reporter.Error
fromReviewError suppressedErrors links error =
    { ruleName = Rule.errorRuleName error
    , ruleLink = linkToRule links error
    , message = Rule.errorMessage error
    , details = Rule.errorDetails error
    , range = Rule.errorRange error
    , fixesHash = Maybe.map Reporter.hashFixes (Rule.errorFixes error)
    , suppressed = SuppressedErrors.member error suppressedErrors
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
        , updateSuppressedErrors UpdateSuppressedErrors
        , collectLinks ReceivedLinks
        , startReview (always GotRequestToReview)
        , startGeneratingSuppressions (always GotRequestToGenerateSuppressionErrors)
        , userConfirmedFix UserConfirmedFix
        , askForFixConfirmationStatus (always RequestedToKnowIfAFixConfirmationIsExpected)
        ]

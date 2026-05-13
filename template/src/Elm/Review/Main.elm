module Elm.Review.Main exposing
    ( Model
    , Msg
    , init
    , subscriptions
    , update
    )

import Array exposing (Array)
import Dict exposing (Dict)
import Elm.Project
import Elm.Review.CliCommunication as CliCommunication
import Elm.Review.CliVersion as CliVersion
import Elm.Review.Color
import Elm.Review.FixOptions as FixOptions
import Elm.Review.InitError as InitError exposing (InitError)
import Elm.Review.Options as Options exposing (Options)
import Elm.Review.RefusedErrorFixes as RefusedErrorFixes exposing (RefusedErrorFixes)
import Elm.Review.Reporter as Reporter
import Elm.Review.Store as Store
import Elm.Review.StoreVersion as StoreVersion exposing (StoreVersion)
import Elm.Review.SuppressedErrors as SuppressedErrors exposing (SuppressedErrors)
import Elm.Review.Testable.Cli as Cli
import Elm.Review.Testable.Cmd as TCmd
import Elm.Review.Testable.Fs as Fs
import Elm.Review.Testable.FsData as FsData
import Elm.Review.Testable.Internal exposing (TCmd, TSub, TTask)
import Elm.Review.Testable.Process as Process
import Elm.Review.Testable.ProcessData as ProcessData exposing (SpawnError)
import Elm.Review.Testable.TSub as TSub
import Elm.Review.Testable.TTask as TTask
import Elm.Review.Text as Text
import Elm.Review.Vendor.Levenshtein as Levenshtein
import Elm.Syntax.Range as Range exposing (Range)
import ElmReview.Color as Color exposing (Color(..))
import ElmReview.Path exposing (Path)
import ElmReview.Problem as Problem exposing (Problem)
import ElmReview.ReportMode as ReportMode exposing (ReportMode(..))
import ElmRun.ProcessExtra as ProcessExtra
import ElmRun.Prompt as Prompt
import Json.Encode as Encode
import Review.Fix as Fix exposing (Fix)
import Review.Fix.FixProblem exposing (FixProblem)
import Review.Project as Project exposing (Project)
import Review.Rule as Rule exposing (Rule)
import ReviewConfig exposing (config)
import Set exposing (Set)



-- MODEL


type alias Model =
    { stdinSupported : Bool
    , options : Options

    --
    , store : Store.Model
    , lastReviewedStoreVersion : StoreVersion
    , promptId : PromptId

    --
    , rules : List Rule
    , isInitialRun : Bool
    , errorsHaveBeenFixedPreviously : Bool

    -- FIX
    , refusedErrorFixes : RefusedErrorFixes
    }


type PromptId
    = PromptId Int


type Msg
    = StoreMsg Store.Msg
    | WroteSuppressionFiles (Result Problem ())
    | FixPromptMsg PromptId FixPromptPayload Prompt.Msg
    | AppliedFixes FixPromptPayload (Result Problem ())


type alias FixPromptPayload =
    { kind : FixPromptKind
    , projectWithFixes : Project
    , rulesWithFixes : List Rule
    , changedFiles : List { filePath : Path, source : String }
    , removedFiles : List Path
    }


type FixPromptKind
    = FixSingle Rule.ReviewError
    | FixAll


initWithOptions :
    Bool
    -> Options
    -> List Rule
    -> ( Model, TCmd Msg )
initWithOptions stdinSupported options rulesFromConfig =
    let
        rules : List Rule
        rules =
            List.map
                (Rule.ignoreErrorsForDirectories options.ignoredDirs >> Rule.ignoreErrorsForFiles options.ignoredFiles)
                rulesFromConfig

        ( store, storeCmd ) =
            Store.init options

        model : Model
        model =
            { stdinSupported = stdinSupported
            , options = options
            , store = store
            , lastReviewedStoreVersion = StoreVersion.zero
            , promptId = PromptId 0
            , rules = rules
            , isInitialRun = True
            , errorsHaveBeenFixedPreviously = False
            , refusedErrorFixes = RefusedErrorFixes.empty
            }
    in
    ( model
    , TCmd.map StoreMsg storeCmd
    )


init : Bool -> List String -> InitError ( Model, TCmd Msg )
init stdinSupported args =
    case Options.parse args of
        Ok options ->
            computeRulesToRun options
                |> InitError.map
                    (\rulesFromConfig ->
                        initWithOptions stdinSupported options rulesFromConfig
                    )

        Err problem ->
            InitError.Problem (roughFormatOptions args) problem


roughFormatOptions : List String -> Problem.FormatOptions {}
roughFormatOptions args =
    { color = Color.noColors
    , reportMode =
        if List.member "--report=json" args || List.member "--report=ndjson" args then
            ReportMode.Json

        else
            ReportMode.HumanReadable
    , debug = List.member "--debug" args
    , attemptFutureRecovery = False
    }


computeRulesToRun : Options -> InitError (List Rule)
computeRulesToRun options =
    let
        problemFormatOptions : () -> Problem.FormatOptions {}
        problemFormatOptions () =
            { color = options.color
            , reportMode = options.reportMode
            , debug = options.debug
            , attemptFutureRecovery = False
            }

        rulesWithIds : List Rule
        rulesWithIds =
            List.indexedMap Rule.withRuleId config

        ( rulesFromConfig, filterNames ) =
            case options.rulesFilter of
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
    in
    if List.isEmpty config then
        { title = "CONFIGURATION IS EMPTY"
        , message =
            \_ -> """Your configuration contains no rules. You can add rules by editing the ReviewConfig.elm file.

I recommend you take a look at the following documents:
  - How to configure elm-review: https://github.com/jfmengels/elm-review/#Configuration
  - When to write or enable a rule: https://github.com/jfmengels/elm-review/#when-to-write-or-enable-a-rule"""
        }
            |> Problem.from Problem.Recoverable
            |> InitError.Problem (problemFormatOptions ())

    else if not (List.isEmpty filterNames) then
        unknownRulesFilterMessage
            { ruleNames =
                List.map Rule.ruleName config
                    |> Set.fromList
                    |> Set.toList
            , filterNames = filterNames
            }
            |> InitError.Problem (problemFormatOptions ())

    else
        case List.filterMap getConfigurationError config of
            (_ :: _) as configurationErrors ->
                case options.reportMode of
                    HumanReadable ->
                        Reporter.formatConfigurationErrors
                            { detailsMode = options.detailsMode
                            , configurationErrors = configurationErrors
                            }
                            |> Text.toAnsi options.supportsColor
                            |> InitError.StringProblem

                    Json ->
                        -- TODO Keep order of keys. Should work out of the box if Encode is implemented as Elm's Json.Encode
                        printJson
                            options.debug
                            (encodeConfigurationErrors options configurationErrors)
                            (Encode.object [])
                            |> InitError.StringProblem

                    NDJson ->
                        printNDJson (encodeConfigurationErrorsForNDJson options configurationErrors)
                            |> InitError.StringProblem

            [] ->
                List.map
                    (Rule.ignoreErrorsForDirectories options.ignoredDirs >> Rule.ignoreErrorsForFiles options.ignoredFiles)
                    rulesFromConfig
                    |> InitError.Success


getConfigurationError : Rule -> Maybe Reporter.Error
getConfigurationError rule =
    case Rule.getConfigurationError rule of
        Just configurationError ->
            Just
                { ruleName = Rule.ruleName rule
                , ruleLink = Nothing
                , message = configurationError.message
                , details = configurationError.details
                , range = Range.empty
                , providesFix = False
                , fixProblem = Nothing
                , providesFileRemovalFix = False
                , suppressed = False
                }

        Nothing ->
            Nothing


unknownRulesFilterMessage : { ruleNames : List String, filterNames : List String } -> Problem
unknownRulesFilterMessage { ruleNames, filterNames } =
    let
        unknownRulesMessage : String
        unknownRulesMessage =
            filterNames
                |> List.map (\filterName -> "- " ++ filterName ++ ". Did you mean:\n  - " ++ String.join "\n  - " (closestNames ruleNames filterName))
                |> String.join "\n\n"
    in
    Problem.from Problem.Unrecoverable
        { title = "UNKNOWN FILTERED RULE(S)"
        , message =
            \_ -> """You requested to only run several rules, but I could not find some of them.

""" ++ unknownRulesMessage
        }


closestNames : List String -> String -> List String
closestNames names name =
    names
        |> List.sortBy (Levenshtein.distance name)
        |> List.take 3



-- UPDATE


stopBecauseOfProblem : Model -> Problem -> TCmd msg
stopBecauseOfProblem model problem =
    Problem.stop
        { color = model.options.color
        , reportMode = model.options.reportMode
        , debug = model.options.debug
        , attemptFutureRecovery = model.options.watch
        }
        problem


update : Msg -> Model -> ( Model, TCmd Msg )
update msg model =
    case msg of
        StoreMsg storeMsg ->
            let
                ( store, cmd ) =
                    Store.update
                        model.options
                        storeMsg
                        model.store
            in
            startReviewIfNoPendingTasks
                ( { model | store = store }
                , TCmd.map StoreMsg cmd
                )

        WroteSuppressionFiles result ->
            ( model
            , case result of
                Ok () ->
                    TCmd.none

                Err problem ->
                    stopBecauseOfProblem model problem
            )

        FixPromptMsg promptId payload fixPromptMsg ->
            if promptId == model.promptId then
                case Prompt.update fixPromptMsg of
                    Prompt.Accepted ->
                        ( model, applyFixChanges model.options payload )

                    Prompt.TriggerCmd cmd ->
                        ( model
                        , TCmd.map (FixPromptMsg promptId payload) cmd
                        )

                    Prompt.Refused ->
                        handleFixRefused payload.kind model

            else
                ( model, TCmd.none )

        AppliedFixes { projectWithFixes, rulesWithFixes } result ->
            case result of
                Ok () ->
                    let
                        ( store, cmd ) =
                            Store.applyChangesFromFix
                                model.options
                                projectWithFixes
                                model.store
                    in
                    ( { model
                        | store = store
                        , rules = rulesWithFixes
                        , errorsHaveBeenFixedPreviously = True
                      }
                    , TCmd.map StoreMsg cmd
                    )

                Err problem ->
                    ( model
                    , stopBecauseOfProblem model problem
                    )


applyFixChanges : Options -> FixPromptPayload -> TCmd Msg
applyFixChanges options fixPayload =
    TTask.map2 always
        (fixPayload.changedFiles
            |> TTask.mapAllAndIgnore (\changedFile -> writeChangedFile options changedFile)
        )
        (TTask.mapAllAndIgnore (\filePath -> Fs.deleteFile filePath) fixPayload.removedFiles
            |> TTask.mapError (\error -> Problem.unexpectedError "while deleting files as part of the automatic fixes" (FsData.errorToString error))
        )
        |> TTask.attempt (AppliedFixes fixPayload)


writeChangedFile : Options -> { filePath : Path, source : String } -> TTask Problem ()
writeChangedFile options { filePath, source } =
    if String.endsWith "*.elm" filePath then
        Fs.writeTextFile filePath source
            |> TTask.mapError (\error -> Problem.unexpectedError "while applying automatic fixes" (FsData.errorToString error))

    else
        Process.run
            (Maybe.withDefault "elm-format" options.elmFormatPath)
            { args = [ "--elm-version=0.19", "--stdin", "--output", filePath ]
            , cwd = Nothing
            , env = Nothing
            , stdin = ProcessData.TextStdin source
            , stdout = ProcessData.stdoutSpec options.debug
            , stderr = ProcessData.CaptureStderr { maxBytes = 1024, onOverflow = ProcessData.TruncateOutput }
            }
            |> TTask.mapError
                (\error ->
                    case error of
                        ProcessData.ProcessRunError processError ->
                            Problem.unexpectedError "while applying automatic fixes and running elm-format" (ProcessData.errorToString processError)

                        ProcessData.CommandNotFound ->
                            elmFormatNotFoundError options.elmFormatPath

                        ProcessData.CommandFailed { stderr } ->
                            Problem.unexpectedError ("while formatting " ++ filePath ++ " with elm-format") (Maybe.withDefault "No output from elm-format." stderr)
                )
            |> TTask.map (\_ -> ())


elmFormatNotFoundError elmFormatPath =
    { title = "ELM-FORMAT NOT FOUND"
    , message =
        \c ->
            case elmFormatPath of
                Just path ->
                    "I could not find the executable for " ++ c MagentaBright "elm-format" ++ " at the location you specified: \n  " ++ path

                Nothing ->
                    "I could not find the executable for " ++ c MagentaBright "elm-format" ++ """

A few options:
- Install it globally.
- Add it to your project through `npm`.
- Specify the path using """ ++ c Cyan "--elm-format-path <path-to-elm-format>" ++ "."
    }
        |> Problem.from Problem.Unrecoverable


handleFixRefused : FixPromptKind -> Model -> ( Model, TCmd Msg )
handleFixRefused fixPromptKind model =
    let
        project : Project
        project =
            Store.project model.store
    in
    case fixPromptKind of
        FixSingle error ->
            { model | refusedErrorFixes = RefusedErrorFixes.insert error model.refusedErrorFixes }
                |> runReview { fixesAllowed = True } project
                |> reportOrFix

        FixAll ->
            model
                |> runReview { fixesAllowed = False } project
                |> makeReport (Store.suppressedErrors model.store)


startReviewIfNoPendingTasks : ( Model, TCmd Msg ) -> ( Model, TCmd Msg )
startReviewIfNoPendingTasks (( model, cmd ) as unchanged) =
    case Store.checkReadiness model.store of
        Store.Ready version ->
            if version == model.lastReviewedStoreVersion then
                unchanged

            else if model.options.suppress then
                let
                    res : { model : Model, result : RunReviewResult }
                    res =
                        runReview { fixesAllowed = False } (Store.project model.store) model
                in
                ( res.model
                , TCmd.batch
                    [ case
                        res.result.reviewErrors
                            |> SuppressedErrors.fromReviewErrors
                            |> SuppressedErrors.write model.options []
                      of
                        Just task ->
                            TTask.attempt WroteSuppressionFiles task

                        Nothing ->
                            TCmd.none
                    , case model.options.reportMode of
                        HumanReadable ->
                            Cli.printlnStdout
                                ("I created suppressions files in "
                                    ++ Color.toAnsi model.options.color Color.Orange (SuppressedErrors.suppressedFolder model.options)
                                )

                        Json ->
                            TCmd.none

                        NDJson ->
                            TCmd.none
                    , cmd
                    , Cli.exit 0
                    ]
                )

            else
                let
                    ( newModel, newCmd ) =
                        model
                            |> runReview { fixesAllowed = True } (Store.project model.store)
                            |> reportOrFix
                in
                ( newModel
                , TCmd.batch [ cmd, newCmd ]
                )

        Store.NotReady ->
            unchanged

        Store.Failure problem ->
            ( model
            , stopBecauseOfProblem model problem
            )


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


type alias RunReviewResult =
    { reviewErrors : List Rule.ReviewError
    , reviewErrorsAfterSuppression : List Rule.ReviewError
    , rules : List Rule
    , project : Project
    , fixedErrors : Dict String (List Rule.ReviewError)
    , extracts : Dict String Encode.Value
    }


runReview : { fixesAllowed : Bool } -> Project -> Model -> { model : Model, result : RunReviewResult }
runReview fixesAllowed initialProject model =
    let
        suppressedErrors : SuppressedErrors
        suppressedErrors =
            Store.suppressedErrors model.store

        { errors, rules, project, extracts, fixedErrors } =
            initialProject
                |> CliCommunication.timerStart model.options.communicationKey "run-review"
                |> Rule.reviewV3
                    (Options.toReviewOptions model.options fixesAllowed model.refusedErrorFixes
                        |> SuppressedErrors.addToReviewOptions suppressedErrors
                    )
                    model.rules
                |> CliCommunication.timerEnd model.options.communicationKey "run-review"

        newModel : Model
        newModel =
            { model
                | rules =
                    if model.isInitialRun || model.options.fixMode == FixOptions.DontFix then
                        rules

                    else
                        model.rules
                , isInitialRun = False
                , store =
                    if model.options.fixMode == FixOptions.DontFix then
                        Store.setProject project model.store

                    else
                        model.store
            }
    in
    { model = newModel
    , result =
        { reviewErrors = errors
        , reviewErrorsAfterSuppression =
            errors
                |> CliCommunication.timerStart model.options.communicationKey "apply-suppressions"
                |> SuppressedErrors.apply model.options.unsuppressMode suppressedErrors
                |> CliCommunication.timerEnd model.options.communicationKey "apply-suppressions"
        , rules = rules
        , project = project
        , fixedErrors = fixedErrors
        , extracts = extracts
        }
    }


reportOrFix : { model : Model, result : RunReviewResult } -> ( Model, TCmd Msg )
reportOrFix input =
    case input.model.options.fixMode of
        FixOptions.DontFix ->
            input
                |> CliCommunication.timerStart input.model.options.communicationKey "process-errors"
                |> makeReport (Store.suppressedErrors input.model.store)
                |> CliCommunication.timerEnd input.model.options.communicationKey "process-errors"

        FixOptions.Fix ->
            applyFixesAfterReview input

        FixOptions.FixAll ->
            applyFixesAfterReview input


makeReport : SuppressedErrors -> { model : Model, result : RunReviewResult } -> ( Model, TCmd Msg )
makeReport previousSuppressedErrors input =
    let
        ( model, suppressionCmd ) =
            saveRunReviewResultsInModel input
    in
    ( model
    , TCmd.batch
        [ suppressionCmd
        , printReport previousSuppressedErrors input.result model
        ]
    )


saveRunReviewResultsInModel : { model : Model, result : RunReviewResult } -> ( Model, TCmd Msg )
saveRunReviewResultsInModel { model, result } =
    -- TODO Keep this function?
    let
        store : Store.Model
        store =
            model.store
                -- TODO This is not saved in else branch?
                |> Store.setProject result.project

        newModel : Model
        newModel =
            { model
                | store = store
                , rules = result.rules
            }
    in
    if List.isEmpty result.reviewErrorsAfterSuppression && model.options.writeSuppressionFiles then
        let
            suppressedErrors : SuppressedErrors
            suppressedErrors =
                SuppressedErrors.fromReviewErrors result.reviewErrors
        in
        ( { newModel | store = Store.setSuppressedErrors suppressedErrors store }
        , case
            result.reviewErrors
                |> SuppressedErrors.fromReviewErrors
                |> SuppressedErrors.write model.options []
          of
            Just task ->
                TTask.attempt WroteSuppressionFiles task

            Nothing ->
                TCmd.none
        )

    else
        ( newModel, TCmd.none )


printReport : SuppressedErrors -> RunReviewResult -> Model -> TCmd Msg
printReport previousSuppressedErrors result model =
    let
        newSuppressedErrors : SuppressedErrors
        newSuppressedErrors =
            Store.suppressedErrors model.store

        ruleLinks : Dict String String
        ruleLinks =
            Store.ruleLinks model.store
    in
    TCmd.batch
        [ case model.options.reportMode of
            HumanReadable ->
                let
                    filesWithError : List { path : Reporter.FilePath, source : Reporter.Source, errors : List Reporter.Error }
                    filesWithError =
                        groupErrorsByFile (fromReviewError newSuppressedErrors ruleLinks) (Store.project model.store) result.reviewErrorsAfterSuppression
                in
                Reporter.formatReport
                    model.options
                    { suppressedErrors = newSuppressedErrors
                    , originalNumberOfSuppressedErrors = SuppressedErrors.count previousSuppressedErrors
                    , errorsHaveBeenFixedPreviously = model.errorsHaveBeenFixedPreviously
                    }
                    filesWithError
                    |> Text.toAnsi model.options.supportsColor
                    |> Cli.printlnStdout

            Json ->
                let
                    errorsByFile : List { path : Reporter.FilePath, source : Reporter.Source, errors : List Rule.ReviewError }
                    errorsByFile =
                        groupErrorsByFile identity (Store.project model.store) result.reviewErrors

                    errors : Encode.Value
                    errors =
                        Encode.list
                            (encodeErrorByFile
                                model.options
                                { suppressedErrors = newSuppressedErrors
                                , reviewErrorsAfterSuppression = result.reviewErrorsAfterSuppression
                                }
                                ruleLinks
                            )
                            errorsByFile
                in
                printJson
                    model.options.debug
                    errors
                    (Encode.dict identity identity result.extracts)
                    |> Cli.printlnStdout

            NDJson ->
                let
                    errorsByFile : List { path : Reporter.FilePath, source : Reporter.Source, errors : List Rule.ReviewError }
                    errorsByFile =
                        groupErrorsByFile identity (Store.project model.store) result.reviewErrors
                in
                errorsByFile
                    |> List.concatMap
                        (encodeErrorsForNDJson
                            model.options
                            { suppressedErrors = newSuppressedErrors
                            , reviewErrorsAfterSuppression = result.reviewErrorsAfterSuppression
                            }
                            ruleLinks
                        )
                    |> printNDJson
                    |> Cli.printlnStdout
        , if model.options.watch then
            TCmd.none

          else if List.isEmpty result.reviewErrorsAfterSuppression then
            Cli.exit 0

          else
            Cli.exit 1
        ]


printJson : Bool -> Encode.Value -> Encode.Value -> String
printJson debug errors extracts =
    let
        indent : Int
        indent =
            if debug then
                2

            else
                0
    in
    Encode.object
        [ ( "version", Encode.string "1" )
        , ( "cliVersion", Encode.string CliVersion.version )
        , ( "type", Encode.string "review-errors" )
        , ( "errors", errors )
        , ( "extracts", extracts )
        ]
        |> Encode.encode indent


printNDJson : List Encode.Value -> String
printNDJson lines =
    lines
        |> List.map (Encode.encode 0)
        |> String.join "\n"


encodeErrorByFile :
    Options
    ->
        { suppressedErrors : SuppressedErrors
        , reviewErrorsAfterSuppression : List Rule.ReviewError
        }
    -> Dict String String
    -> { path : Reporter.FilePath, source : Reporter.Source, errors : List Rule.ReviewError }
    -> Encode.Value
encodeErrorByFile options suppressedErrorsData links file =
    Encode.object
        [ ( "path", encodeFilePath file.path )
        , ( "errors"
          , file.errors
                |> List.sortWith
                    (\a b ->
                        case Reporter.compareRange (Rule.errorRange a) (Rule.errorRange b) of
                            EQ ->
                                compare (Rule.errorRuleName a) (Rule.errorRuleName b)

                            order ->
                                order
                    )
                |> Encode.list (encodeError options suppressedErrorsData Nothing links file.source)
          )
        ]


encodeErrorsForNDJson :
    Options
    ->
        { suppressedErrors : SuppressedErrors
        , reviewErrorsAfterSuppression : List Rule.ReviewError
        }
    -> Dict String String
    -> { path : Reporter.FilePath, source : Reporter.Source, errors : List Rule.ReviewError }
    -> List Encode.Value
encodeErrorsForNDJson options suppressedErrorsData links file =
    List.map
        (encodeError
            options
            suppressedErrorsData
            (Just ( "path", encodeFilePath file.path ))
            links
            file.source
        )
        file.errors


encodeConfigurationErrors : Options -> List Reporter.Error -> Encode.Value
encodeConfigurationErrors options errors =
    Encode.object
        [ ( "path", Encode.null )
        , ( "errors", Encode.list (encodeConfigurationError options []) errors )
        ]


encodeConfigurationErrorsForNDJson : Options -> List Reporter.Error -> List Encode.Value
encodeConfigurationErrorsForNDJson options errors =
    List.map (encodeConfigurationError options [ ( "path", Encode.null ) ]) errors


encodeFilePath : Reporter.FilePath -> Encode.Value
encodeFilePath filePath =
    case filePath of
        Reporter.FilePath path ->
            Encode.string path

        Reporter.Global ->
            Encode.null


encodeError :
    Options
    ->
        { suppressedErrors : SuppressedErrors
        , reviewErrorsAfterSuppression : List Rule.ReviewError
        }
    -> Maybe ( String, Encode.Value )
    -> Dict String String
    -> Reporter.Source
    -> Rule.ReviewError
    -> Encode.Value
encodeError options { suppressedErrors, reviewErrorsAfterSuppression } pathField links source error =
    let
        originallySuppressed : Bool
        originallySuppressed =
            SuppressedErrors.member error suppressedErrors
    in
    [ pathField
    , Just ( "rule", Encode.string <| Rule.errorRuleName error )
    , Just ( "message", Encode.string <| Rule.errorMessage error )
    , linkToRule links error
        |> Maybe.map (Encode.string >> Tuple.pair "ruleLink")
    , Just ( "details", Encode.list Encode.string <| Rule.errorDetails error )
    , Just ( "region", encodeRange <| Rule.errorRange error )
    , Rule.errorFixes error
        |> Maybe.map (encodeEdits >> Tuple.pair "fix")
    , case Rule.errorFixesV2 error of
        Ok (Just fixes) ->
            Just ( "fixV2", encodeFixesV2 fixes )

        Ok Nothing ->
            Nothing

        Err _ ->
            Nothing
    , Just ( "formatted", encodeReport (Reporter.formatIndividualError options source (fromReviewError suppressedErrors links error)) )
    , Just ( "suppressed", Encode.bool (originallySuppressed && not (List.member error reviewErrorsAfterSuppression)) )
    , Just ( "originallySuppressed", Encode.bool originallySuppressed )
    ]
        |> List.filterMap identity
        |> Encode.object


encodeConfigurationError : Options -> List ( String, Encode.Value ) -> Reporter.Error -> Encode.Value
encodeConfigurationError options pathField error =
    pathField
        ++ [ ( "rule", Encode.string error.ruleName )
           , ( "message", Encode.string error.message )
           , ( "details", Encode.list Encode.string error.details )
           , ( "region", encodeRange Range.empty )
           , ( "formatted", encodeReport (Reporter.formatIndividualError { options | fixExplanation = FixOptions.Succinct } (Reporter.Source Array.empty) error) )
           ]
        |> Encode.object


linkToRule : Dict String String -> Rule.ReviewError -> Maybe String
linkToRule links error =
    Dict.get (Rule.errorRuleName error) links


encodeEdits : List Fix -> Encode.Value
encodeEdits fixes =
    Encode.list (Fix.toRecord >> encodeFix) fixes


encodeFixesV2 : List ( String, Maybe (List Fix) ) -> Encode.Value
encodeFixesV2 fixes =
    Encode.list
        (\( path, fix ) ->
            Encode.object
                [ ( "path", Encode.string path )
                , ( "fix", encodeFixKind fix )
                ]
        )
        fixes


encodeFixKind : Maybe (List Fix) -> Encode.Value
encodeFixKind fixKind =
    case fixKind of
        Just edits ->
            Encode.object
                [ ( "kind", Encode.string "edit" )
                , ( "edits", encodeEdits edits )
                ]

        Nothing ->
            Encode.object
                [ ( "kind", Encode.string "remove" )
                ]


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


applyFixesAfterReview : { model : Model, result : RunReviewResult } -> ( Model, TCmd Msg )
applyFixesAfterReview ({ model, result } as input) =
    case numberOfErrors result.fixedErrors of
        Nothing ->
            makeReport (Store.suppressedErrors model.store) input

        Just nbErrors ->
            case Project.diffV2 { before = Store.project model.store, after = result.project } of
                [] ->
                    makeReport (Store.suppressedErrors model.store) input

                diffs ->
                    sendFixPrompt diffs result nbErrors model


sendFixPrompt : List FixedFile -> RunReviewResult -> NumberOfErrors -> Model -> ( Model, TCmd Msg )
sendFixPrompt diffs result nbErrors model =
    let
        changedFiles : List { filePath : Path, source : String }
        changedFiles =
            List.filterMap
                (\{ path, diff } ->
                    case diff of
                        Project.Edited { after } ->
                            Just
                                { filePath = path
                                , source = after
                                }

                        Project.Removed ->
                            Nothing
                )
                diffs

        removedFiles : List Path
        removedFiles =
            List.filterMap
                (\{ path, diff } ->
                    case diff of
                        Project.Edited _ ->
                            Nothing

                        Project.Removed ->
                            Just path
                )
                diffs

        fixKind : FixPromptKind
        fixKind =
            case nbErrors of
                OneError _ error ->
                    FixSingle error

                MultipleErrors _ ->
                    FixAll

        fixPayload : FixPromptPayload
        fixPayload =
            { kind = fixKind
            , projectWithFixes = result.project
            , rulesWithFixes = result.rules
            , changedFiles = changedFiles
            , removedFiles = removedFiles
            }
    in
    if shouldPromptForFix model then
        let
            proposal : List Reporter.TextContent
            proposal =
                case nbErrors of
                    OneError filePath error ->
                        Reporter.formatSingleFixProposal
                            model.options
                            (pathAndSource (Store.project model.store) filePath)
                            (fromReviewError (Store.suppressedErrors model.store) (Store.ruleLinks model.store) error)
                            diffs

                    MultipleErrors _ ->
                        confirmationForMultipleFixesPrompt model diffs result.fixedErrors

            promptId : PromptId
            promptId =
                incrementPrompt model.promptId
        in
        ( { model | promptId = promptId }
        , Prompt.prompt
            { color = model.options.color
            , priorMessage = Just (Text.toAnsi model.options.supportsColor proposal)
            , question =
                \_ ->
                    case nbErrors of
                        OneError _ _ ->
                            "Do you wish to apply this fix?"

                        MultipleErrors numberOfFixedErrors ->
                            "Do you wish to apply the result of these " ++ String.fromInt numberOfFixedErrors ++ " fixes?"
            }
            |> TCmd.map (FixPromptMsg promptId fixPayload)
        )

    else
        ( model, applyFixChanges model.options fixPayload )


shouldPromptForFix : Model -> Bool
shouldPromptForFix model =
    if model.options.skipFixPrompt then
        False

    else
        model.stdinSupported


incrementPrompt : PromptId -> PromptId
incrementPrompt (PromptId promptId) =
    PromptId (promptId + 1)


pathAndSource : Project -> String -> { path : Reporter.FilePath, source : Reporter.Source }
pathAndSource project path =
    if path == "GLOBAL ERROR" then
        { path = Reporter.Global, source = Reporter.Source Array.empty }

    else
        let
            fileSource : Maybe String
            fileSource =
                if path == "elm.json" then
                    Project.elmJson project |> Maybe.map .raw

                else if path == "README.md" then
                    Project.readme project |> Maybe.map .content

                else
                    case find (\module_ -> module_.path == path) (Project.modules project) of
                        Just { source } ->
                            Just source

                        Nothing ->
                            Dict.get path (Project.extraFiles project)

            fileLines : Array String
            fileLines =
                case fileSource of
                    Just source ->
                        source |> String.lines |> Array.fromList

                    Nothing ->
                        Array.empty
        in
        { path = Reporter.FilePath path, source = Reporter.Source fileLines }


confirmationForMultipleFixesPrompt : Model -> List FixedFile -> Dict String (List Rule.ReviewError) -> List Reporter.TextContent
confirmationForMultipleFixesPrompt model diffs fixedErrors =
    let
        errorsForFile : Dict String (List Reporter.Error)
        errorsForFile =
            Dict.foldl
                (\_ errors acc ->
                    List.foldl
                        (\error subAcc ->
                            case Rule.errorFixesV2 error of
                                Ok (Just fixedFiles) ->
                                    List.foldl
                                        (\( fixedFile, _ ) subSubAcc ->
                                            Dict.update fixedFile
                                                (\previousErrors ->
                                                    fromReviewError (Store.suppressedErrors model.store) (Store.ruleLinks model.store) error
                                                        :: Maybe.withDefault [] previousErrors
                                                        |> Just
                                                )
                                                subSubAcc
                                        )
                                        subAcc
                                        fixedFiles

                                Ok Nothing ->
                                    subAcc

                                Err _ ->
                                    subAcc
                        )
                        acc
                        errors
                )
                Dict.empty
                fixedErrors
    in
    Reporter.formatFixProposals model.options.fileRemovalFixesEnabled errorsForFile diffs


type NumberOfErrors
    = OneError String Rule.ReviewError
    | MultipleErrors Int


numberOfErrors : Dict String (List Rule.ReviewError) -> Maybe NumberOfErrors
numberOfErrors dict =
    case Dict.toList dict of
        [] ->
            Nothing

        [ ( filePath, [ singleError ] ) ] ->
            Just (OneError filePath singleError)

        list ->
            Just (MultipleErrors (List.length list))


type alias FixedFile =
    { path : String
    , diff : Project.Diff
    }


groupErrorsByFile : (Rule.ReviewError -> reportError) -> Project -> List Rule.ReviewError -> List { path : Reporter.FilePath, source : Reporter.Source, errors : List reportError }
groupErrorsByFile mapper project errors =
    if List.isEmpty errors then
        []

    else if not (List.isEmpty (Project.modulesThatFailedToParse project)) then
        List.map
            (\error ->
                { path = Reporter.FilePath (Rule.errorFilePath error)
                , source = Reporter.Source Array.empty
                , errors = [ mapper error ]
                }
            )
            errors

    else
        let
            findSource_ : String -> String
            findSource_ =
                findSource project
        in
        errors
            |> groupPerPath
            |> Dict.toList
            |> List.sortBy orderFiles
            |> List.map
                (\( path, errorsForFile ) ->
                    if path == "GLOBAL ERROR" then
                        { path = Reporter.Global
                        , source = Reporter.Source Array.empty
                        , errors = List.map mapper errorsForFile
                        }

                    else
                        { path = Reporter.FilePath path
                        , source =
                            if List.all (\error -> Rule.errorRange error == Range.empty) errorsForFile then
                                Reporter.Source Array.empty

                            else
                                findSource_ path
                                    |> String.lines
                                    |> Array.fromList
                                    |> Reporter.Source
                        , errors = List.map mapper errorsForFile
                        }
                )


groupPerPath : List Rule.ReviewError -> Dict String (List Rule.ReviewError)
groupPerPath errors =
    List.foldl
        (\error dict ->
            let
                path : String
                path =
                    Rule.errorFilePath error
            in
            case Dict.get path dict of
                Nothing ->
                    Dict.insert path [ error ] dict

                Just errorsSoFar ->
                    Dict.insert path (error :: errorsSoFar) dict
        )
        Dict.empty
        errors


orderFiles : ( String, b ) -> ( Int, String )
orderFiles ( path, _ ) =
    if path == "GLOBAL ERROR" then
        ( 0, "" )

    else if path == "elm.json" then
        ( 1, "" )

    else if path == "README.md" then
        ( 2, "" )

    else
        ( -1, path )


findSource : Project -> String -> String
findSource project =
    let
        elmModules : Dict String String
        elmModules =
            -- TODO Add some kind of `Project.getModuleByPath path` to `jfmengels/elm-review` to avoid unnecessary conversion
            -- or simply one returning a `Dict PathAsString ProjectModules`
            List.foldl (\{ path, source } acc -> Dict.insert path source acc) Dict.empty (Project.modules project)

        elmJson : Maybe { path : String, raw : String, project : Elm.Project.Project }
        elmJson =
            Project.elmJson project

        readme : Maybe { path : String, content : String }
        readme =
            Project.readme project
    in
    \filePath ->
        case Dict.get filePath elmModules of
            Just source ->
                source

            Nothing ->
                case Dict.get filePath (Project.extraFiles project) of
                    Just source ->
                        source

                    Nothing ->
                        case maybeWithCondition .path .raw filePath elmJson of
                            Just source ->
                                source

                            Nothing ->
                                case maybeWithCondition .path .content filePath readme of
                                    Just source ->
                                        source

                                    Nothing ->
                                        ""


maybeWithCondition : (a -> String) -> (a -> String) -> String -> Maybe a -> Maybe String
maybeWithCondition getFilePath getSource filePath maybe =
    case maybe of
        Nothing ->
            Nothing

        Just a ->
            if getFilePath a == filePath then
                Just (getSource a)

            else
                Nothing


fromReviewError : SuppressedErrors -> Dict String String -> Rule.ReviewError -> Reporter.Error
fromReviewError suppressedErrors links error =
    let
        fixes : Result FixProblem (Maybe (List ( String, Maybe (List Fix) )))
        fixes =
            Rule.errorFixesV2 error

        providesFix : Bool
        providesFix =
            case fixes of
                Ok Nothing ->
                    False

                Ok (Just _) ->
                    True

                Err _ ->
                    True
    in
    { ruleName = Rule.errorRuleName error
    , ruleLink = linkToRule links error
    , message = Rule.errorMessage error
    , details = Rule.errorDetails error
    , range = Rule.errorRange error
    , providesFix = providesFix
    , fixProblem =
        case fixes of
            Ok Nothing ->
                Nothing

            Ok (Just _) ->
                Nothing

            Err fixProblem ->
                Just fixProblem
    , providesFileRemovalFix =
        case fixes of
            Ok (Just fixes_) ->
                hasFileRemovalFixes fixes_

            Ok Nothing ->
                False

            Err _ ->
                False
    , suppressed = SuppressedErrors.member error suppressedErrors
    }


hasFileRemovalFixes : List ( String, Maybe (List Fix) ) -> Bool
hasFileRemovalFixes fixes =
    List.any (\( _, fix ) -> fix == Nothing) fixes



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
        let
            fields : List ( String, Encode.Value )
            fields =
                []
                    |> maybeMapAndCons (\href_ -> ( "href", Encode.string href_ )) href
                    |> maybeMapAndCons (\color_ -> ( "color", Encode.string (Elm.Review.Color.toHex color_) )) color
        in
        Encode.object (( "string", Encode.string str ) :: fields)


maybeMapAndCons : (a -> b) -> Maybe a -> List b -> List b
maybeMapAndCons fn maybe list =
    case maybe of
        Just x ->
            fn x :: list

        Nothing ->
            list


subscriptions : Model -> TSub Msg
subscriptions model =
    if model.options.watch then
        Store.subscriptions model.options model.store
            |> TSub.map StoreMsg

    else
        TSub.none

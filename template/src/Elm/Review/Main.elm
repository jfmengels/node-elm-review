port module Elm.Review.Main exposing (ModelWrapper, Msg, main)

import Array exposing (Array)
import Cli exposing (Env)
import Dict exposing (Dict)
import Elm.Project
import Elm.Review.CliCommunication as CliCommunication
import Elm.Review.CliVersion as CliVersion
import Elm.Review.Color
import Elm.Review.FixOptions as FixOptions
import Elm.Review.Options as Options exposing (Options)
import Elm.Review.RefusedErrorFixes as RefusedErrorFixes exposing (RefusedErrorFixes)
import Elm.Review.Reporter as Reporter
import Elm.Review.RunEnvironment exposing (RunEnvironment)
import Elm.Review.Store as Store
import Elm.Review.SuppressedErrors as SuppressedErrors exposing (SuppressedErrors)
import Elm.Review.Text as Text
import Elm.Review.Vendor.Levenshtein as Levenshtein
import Elm.Syntax.Range as Range exposing (Range)
import ElmReview.Color as Color exposing (Color(..))
import ElmReview.Path exposing (Path)
import ElmReview.Problem as Problem exposing (Problem)
import ElmReview.ReportMode as ReportMode exposing (ReportMode(..))
import ElmRun.Prompt as Prompt
import ElmRun.TaskExtra as TaskExtra
import Fs exposing (FileSystem, FsError(..))
import Json.Encode as Encode
import Review.Fix as Fix exposing (Fix)
import Review.Fix.FixProblem exposing (FixProblem)
import Review.Project as Project exposing (Project)
import Review.Rule as Rule exposing (Rule)
import ReviewConfig exposing (config)
import Set exposing (Set)
import Task



-- PORTS


port requestReadingFiles : List { files : List { pattern : String, included : Bool }, excludedDirectories : List String } -> Cmd msg



-- PROGRAM


main : Cli.Program ModelWrapper Msg
main =
    Cli.program
        { init = init
        , update = updateWrapper
        , subscriptions = \_ -> Sub.none
        }



-- MODEL


type alias Model =
    { env : Env
    , fs : FileSystem
    , options : Options
    , runEnvironment : RunEnvironment

    --
    , store : Store.Model
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


type ModelWrapper
    = Done
    | Running Model


type Msg
    = StoreMsg Store.Msg
    | WroteSuppressionFiles (Result Problem ())
    | FixPromptMsg PromptId FixPromptPayload Prompt.Msg
    | AppliedFixes (Result Fs.FsError ())


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


init : Env -> ( ModelWrapper, Cmd Msg )
init env =
    case Fs.require env of
        Err err ->
            ( Done
            , { title = "MISSING CAPABILITIES"
              , message = \_ -> "elm-review was run with missing capabilities:\n\n    " ++ err
              }
                |> Problem.from
                |> Problem.exit env.stderr (roughFormatOptions env.args)
            )

        Ok fs ->
            case Options.parse env.args of
                Err error ->
                    ( Done
                    , Problem.exit env.stderr (roughFormatOptions env.args) error
                    )

                Ok options ->
                    initWithOptions env fs options


roughFormatOptions : List String -> Problem.FormatOptions {}
roughFormatOptions args =
    { color = Color.noColors
    , reportMode =
        if List.member "--report=json" args || List.member "--report=ndjson" args then
            ReportMode.Json

        else
            ReportMode.HumanReadable
    , debug = List.member "--debug" args
    }


initWithOptions : Env -> FileSystem -> Options -> ( ModelWrapper, Cmd Msg )
initWithOptions env fs options =
    case computeRulesToRun env options of
        Err cmd ->
            ( Done, cmd )

        Ok rules ->
            initValid env fs options rules


initValid : Env -> FileSystem -> Options -> List Rule -> ( ModelWrapper, Cmd Msg )
initValid env fs options rulesFromConfig =
    let
        rules : List Rule
        rules =
            List.map
                (Rule.ignoreErrorsForDirectories options.ignoredDirs >> Rule.ignoreErrorsForFiles options.ignoredFiles)
                rulesFromConfig

        runEnvironment : RunEnvironment
        runEnvironment =
            { --TODO Get from somewhere
              elmHomePath = "/Users/m1/.elm"
            , -- TODO Get from somewhere
              elmVersion = "0.19.1"
            , reviewFolder = options.reviewFolder
            }

        ( store, storeCmd ) =
            Store.init
                { fs = fs
                , options = options
                , runEnvironment = runEnvironment
                , directoriesToAnalyze = options.directoriesToAnalyze
                }

        model : Model
        model =
            { env = env
            , fs = fs
            , options = options
            , runEnvironment = runEnvironment
            , store = store
            , promptId = PromptId 0
            , rules = rules
            , isInitialRun = True
            , errorsHaveBeenFixedPreviously = False
            , refusedErrorFixes = RefusedErrorFixes.empty
            }
    in
    ( Running model
    , Cmd.batch
        [ rules |> List.concatMap Rule.ruleRequestedFiles |> requestReadingFiles
        , Cmd.map StoreMsg storeCmd
        ]
    )


computeRulesToRun : Env -> Options -> Result (Cmd msg) (List Rule)
computeRulesToRun env options =
    let
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
            |> Problem.from
            |> Problem.exit env.stderr options
            |> Err

    else if not (List.isEmpty filterNames) then
        unknownRulesFilterMessage
            { ruleNames =
                List.map Rule.ruleName config
                    |> Set.fromList
                    |> Set.toList
            , filterNames = filterNames
            }
            |> Problem.exit env.stderr options
            |> Err

    else
        case List.filterMap getConfigurationError config of
            (_ :: _) as configurationErrors ->
                case options.reportMode of
                    HumanReadable ->
                        Cmd.batch
                            [ Reporter.formatConfigurationErrors
                                { detailsMode = options.detailsMode
                                , configurationErrors = configurationErrors
                                }
                                |> Text.toAnsi options.supportsColor
                                |> Cli.println env.stdout
                            , Cli.exit 1
                            ]
                            |> Err

                    Json ->
                        -- TODO Keep order of keys. Should work out of the box if Encode is implemented as Elm's Json.Encode
                        Cmd.batch
                            [ printJson
                                env
                                options.debug
                                (encodeConfigurationErrors options configurationErrors)
                                (Encode.object [])
                            , Cli.exit 1
                            ]
                            |> Err

                    NDJson ->
                        Cmd.batch
                            [ printNDJson env (encodeConfigurationErrorsForNDJson options configurationErrors)
                            , Cli.exit 1
                            ]
                            |> Err

            [] ->
                List.map
                    (Rule.ignoreErrorsForDirectories options.ignoredDirs >> Rule.ignoreErrorsForFiles options.ignoredFiles)
                    rulesFromConfig
                    |> Ok


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
    Problem.from
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


updateWrapper : Msg -> ModelWrapper -> ( ModelWrapper, Cmd Msg )
updateWrapper msg wrapper =
    case wrapper of
        Done ->
            ( wrapper, Cmd.none )

        Running model ->
            update msg model
                |> Tuple.mapFirst Running


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        StoreMsg storeMsg ->
            let
                ( store, cmd ) =
                    Store.update
                        { fs = model.fs
                        , runEnvironment = model.runEnvironment
                        , stderr = model.env.stderr
                        , ignoreProblematicDependencies = model.options.ignoreProblematicDependencies
                        , handleProblem = Problem.exit model.env.stderr model.options
                        }
                        storeMsg
                        model.store
            in
            startReviewIfNoPendingTasks
                ( { model | store = store }
                , Cmd.map StoreMsg cmd
                )

        WroteSuppressionFiles result ->
            ( model
            , case result of
                Ok () ->
                    Cmd.none

                Err problem ->
                    Problem.exit model.env.stderr model.options problem
            )

        FixPromptMsg promptId payload fixPromptMsg ->
            if promptId == model.promptId then
                case Prompt.update fixPromptMsg of
                    Prompt.Accepted ->
                        applyFixChanges payload model

                    Prompt.TriggerCmd cmd ->
                        ( model
                        , Cmd.map (FixPromptMsg promptId payload) cmd
                        )

                    Prompt.Refused ->
                        handleFixRefused payload.kind model

            else
                ( model, Cmd.none )

        AppliedFixes _ ->
            -- TODO Do something?
            ( model, Cmd.none )


applyFixChanges : FixPromptPayload -> Model -> ( Model, Cmd Msg )
applyFixChanges { projectWithFixes, rulesWithFixes, changedFiles, removedFiles } model =
    -- TODO
    -- Support multi file fixes
    -- Remove fixAllProject from Model?
    -- Remove Prompt module?
    -- From JS: askConfirmationToFixWithOptions
    --   - Check if elm.json was modified
    --      - Refetch source-dependencies / dependencies if they changed
    -- From Elm: UserConfirmedFix confirmation ->
    --   - ???
    ( { model
        | store = Store.setProject projectWithFixes model.store
        , rules = rulesWithFixes
      }
    , Task.map2 always
        (changedFiles
            -- TODO Format Elm files
            |> TaskExtra.mapAll (\{ filePath, source } -> Fs.writeTextFile model.fs filePath source)
        )
        (TaskExtra.mapAll (\filePath -> Fs.deleteFile model.fs filePath) removedFiles)
        |> Task.attempt AppliedFixes
    )


handleFixRefused : FixPromptKind -> Model -> ( Model, Cmd Msg )
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


startReviewIfNoPendingTasks : ( Model, Cmd Msg ) -> ( Model, Cmd Msg )
startReviewIfNoPendingTasks (( model, cmd ) as unchanged) =
    if model.isInitialRun then
        case Store.checkReadiness model.store of
            Store.Ready ->
                if model.options.suppress then
                    let
                        res : { model : Model, result : RunReviewResult }
                        res =
                            runReview { fixesAllowed = False } (Store.project model.store) model
                    in
                    ( res.model
                    , Cmd.batch
                        [ case
                            res.result.reviewErrors
                                |> SuppressedErrors.fromReviewErrors
                                |> SuppressedErrors.write model.fs model.options []
                          of
                            Just task ->
                                Task.attempt WroteSuppressionFiles task

                            Nothing ->
                                Cmd.none

                        -- TODO Don't print in JSON report mode
                        , Cli.println model.env.stdout
                            ("I created suppressions files in "
                                ++ Color.toAnsi model.options.color Color.Orange (SuppressedErrors.suppressedFolder model.options)
                            )
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
                    , Cmd.batch [ cmd, newCmd ]
                    )

            Store.NotReady ->
                unchanged

            Store.Failure problem ->
                ( model
                , Problem.exit model.env.stderr model.options problem
                )

    else
        unchanged


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


reportOrFix : { model : Model, result : RunReviewResult } -> ( Model, Cmd Msg )
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


makeReport : SuppressedErrors -> { model : Model, result : RunReviewResult } -> ( Model, Cmd Msg )
makeReport previousSuppressedErrors input =
    let
        ( model, suppressionCmd ) =
            saveRunReviewResultsInModel input
    in
    ( model
    , Cmd.batch
        [ suppressionCmd
        , printReport previousSuppressedErrors input.result model
        ]
    )


saveRunReviewResultsInModel : { model : Model, result : RunReviewResult } -> ( Model, Cmd Msg )
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
                |> SuppressedErrors.write model.fs model.options []
          of
            Just task ->
                Task.attempt WroteSuppressionFiles task

            Nothing ->
                Cmd.none
        )

    else
        ( newModel, Cmd.none )


printReport : SuppressedErrors -> RunReviewResult -> Model -> Cmd Msg
printReport previousSuppressedErrors result model =
    let
        newSuppressedErrors : SuppressedErrors
        newSuppressedErrors =
            Store.suppressedErrors model.store

        ruleLinks : Dict String String
        ruleLinks =
            Store.ruleLinks model.store
    in
    Cmd.batch
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
                    |> Cli.println model.env.stdout

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
                    model.env
                    model.options.debug
                    errors
                    (Encode.dict identity identity result.extracts)

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
                    |> printNDJson model.env
        , if model.options.watch then
            Cmd.none

          else if List.isEmpty result.reviewErrorsAfterSuppression then
            Cli.exit 0

          else
            Cli.exit 1
        ]


printJson : Env -> Bool -> Encode.Value -> Encode.Value -> Cmd msg
printJson env debug errors extracts =
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
        |> Cli.println env.stdout


printNDJson : Env -> List Encode.Value -> Cmd msg
printNDJson env lines =
    lines
        |> List.map (Encode.encode 0)
        |> String.join "\n"
        |> Cli.println env.stdout


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


applyFixesAfterReview : { model : Model, result : RunReviewResult } -> ( Model, Cmd Msg )
applyFixesAfterReview ({ model, result } as input) =
    if Dict.isEmpty result.fixedErrors then
        makeReport (Store.suppressedErrors model.store) input

    else
        case Project.diffV2 { before = Store.project model.store, after = result.project } of
            [] ->
                makeReport (Store.suppressedErrors model.store) input

            diffs ->
                sendFixPrompt diffs result model


sendFixPrompt : List FixedFile -> RunReviewResult -> Model -> ( Model, Cmd Msg )
sendFixPrompt diffs result model =
    case numberOfErrors result.fixedErrors of
        Nothing ->
            ( model, Cmd.none )

        Just nbErrors ->
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
            case model.env.stdin of
                Just stdin ->
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
                        stdin
                        model.env.stdout
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
                        |> Cmd.map (FixPromptMsg promptId fixPayload)
                    )

                Nothing ->
                    -- If there's no stdin, assume the reply is yes.
                    applyFixChanges fixPayload model


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



-- REVIEWING

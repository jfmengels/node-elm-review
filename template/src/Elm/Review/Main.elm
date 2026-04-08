port module Elm.Review.Main exposing (ModelWrapper, Msg, main)

import Array exposing (Array)
import Cli exposing (Env)
import Dict exposing (Dict)
import Elm.Docs
import Elm.Project
import Elm.Review.AstCodec as AstCodec
import Elm.Review.CliCommunication as CliCommunication
import Elm.Review.CliVersion as CliVersion
import Elm.Review.Color as Color
import Elm.Review.File
import Elm.Review.FixOptions as FixOptions
import Elm.Review.FixPrompt as FixPrompt
import Elm.Review.Options as Options exposing (Options)
import Elm.Review.RefusedErrorFixes as RefusedErrorFixes exposing (RefusedErrorFixes)
import Elm.Review.Reporter as Reporter
import Elm.Review.RunEnvironment exposing (RunEnvironment)
import Elm.Review.Store as Store
import Elm.Review.SuppressedErrors as SuppressedErrors exposing (SuppressedErrors)
import Elm.Review.Text as Text
import Elm.Review.Vendor.Levenshtein as Levenshtein
import Elm.Syntax.File
import Elm.Syntax.Range as Range exposing (Range)
import ElmReview.Path exposing (Path)
import ElmReview.ReportMode exposing (ReportMode(..))
import ElmRun.TaskExtra as TaskExtra
import Fs exposing (FileSystem, FsError(..))
import Json.Decode as Decode
import Json.Encode as Encode
import Review.Fix as Fix exposing (Fix)
import Review.Fix.FixProblem exposing (FixProblem)
import Review.Project as Project exposing (Project)
import Review.Project.Dependency as Dependency exposing (Dependency)
import Review.Rule as Rule exposing (Rule)
import ReviewConfig exposing (config)
import Set exposing (Set)
import Task exposing (Task)



-- PORTS


port requestReadingFiles : List { files : List { pattern : String, included : Bool }, excludedDirectories : List String } -> Cmd msg


port collectFile : (Decode.Value -> msg) -> Sub msg


port removeFile : (String -> msg) -> Sub msg


port collectElmJson : (Decode.Value -> msg) -> Sub msg


port collectReadme : (Decode.Value -> msg) -> Sub msg


port collectExtraFiles : (Decode.Value -> msg) -> Sub msg


port collectDependencies : (Decode.Value -> msg) -> Sub msg


port updateSuppressedErrors : (Decode.Value -> msg) -> Sub msg


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


abort : Env -> Bool -> String -> Cmd msg
abort env supportsColor message =
    abortWithDetails
        env
        supportsColor
        { title = "UNEXPECTED CRASH"
        , message = "I encountered an unexpected crash with the following error message:\n\n" ++ String.trim message
        }


abortWithDetails : Env -> Bool -> { title : String, message : String } -> Cmd msg
abortWithDetails env supportsColor { title, message } =
    let
        titleText : String
        titleText =
            "-- " ++ title ++ String.repeat (80 - String.length title - 4) "-"

        colorize : String -> String
        colorize str =
            if supportsColor then
                "\u{001B}[32m" ++ str ++ "\u{001B}[39m"

            else
                str
    in
    Cmd.batch
        [ Cli.println env.stderr (colorize titleText ++ "\n\n" ++ String.trim message)
        , Cli.exit 1
        ]



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
    , fixPrompt : FixPrompt.Model

    --
    , rules : List Rule
    , fixAllRules : List Rule
    , isInitialRun : Bool
    , reviewErrors : List Rule.ReviewError
    , reviewErrorsAfterSuppression : List Rule.ReviewError
    , errorsHaveBeenFixedPreviously : Bool
    , extracts : Dict String Encode.Value

    -- FIX
    , refusedErrorFixes : RefusedErrorFixes
    , errorAwaitingConfirmation : AwaitingConfirmation

    -- FIX ALL
    , fixAllResultProject : Project
    , fixAllErrors : Dict String (List Rule.ReviewError)
    }


type AwaitingConfirmation
    = NotAwaiting
    | AwaitingError Rule.ReviewError
    | AwaitingFixAll


type ModelWrapper
    = Done
    | Running Model


type Msg
    = StoreMsg Store.Msg
    | SuppressedErrorsMsg SuppressedErrors.Msg
    | FixPromptMsg (FixPrompt.Msg FixPromptPayload)
    | AppliedFixes (Result Fs.FsError ())


type alias FixPromptPayload =
    { changedFiles : List { filePath : Path, source : String }
    , removedFiles : List Path
    }


init : Env -> ( ModelWrapper, Cmd Msg )
init env =
    case Fs.require env of
        Err msg ->
            ( Done
            , Cmd.batch
                [ Cli.println env.stderr (env.programName ++ ": " ++ msg)
                , Cli.exit 1
                ]
            )

        Ok fs ->
            case Options.parse env.args of
                Err error ->
                    ( Done
                    , Cmd.batch
                        [ Cli.println env.stderr error
                        , Cli.exit 1
                        ]
                    )

                Ok options ->
                    initWithOptions env fs options


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
            , fixPrompt = FixPrompt.init
            , rules = rules
            , isInitialRun = True
            , reviewErrors = []
            , reviewErrorsAfterSuppression = []
            , errorsHaveBeenFixedPreviously = False
            , refusedErrorFixes = RefusedErrorFixes.empty
            , errorAwaitingConfirmation = NotAwaiting
            , fixAllRules = rules
            , fixAllResultProject = Project.new
            , fixAllErrors = Dict.empty
            , extracts = Dict.empty
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
        abortWithDetails
            env
            options.supportsColor
            { title = "CONFIGURATION IS EMPTY"
            , message =
                """Your configuration contains no rules. You can add rules by editing the ReviewConfig.elm file.

I recommend you take a look at the following documents:
  - How to configure elm-review: https://github.com/jfmengels/elm-review/#Configuration
  - When to write or enable a rule: https://github.com/jfmengels/elm-review/#when-to-write-or-enable-a-rule"""
            }
            |> Err

    else if not (List.isEmpty filterNames) then
        abortWithDetails
            env
            options.supportsColor
            (unknownRulesFilterMessage
                { ruleNames =
                    List.map Rule.ruleName config
                        |> Set.fromList
                        |> Set.toList
                , filterNames = filterNames
                }
            )
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



-- UPDATE


type MsgOld
    = ReceivedFile Decode.Value
    | RemovedFile String
    | ReceivedElmJsonOld Decode.Value
    | ReceivedReadmeOld Decode.Value
    | ReceivedExtraFiles Decode.Value
    | ReceivedDependencies Decode.Value
    | UpdateSuppressedErrors Decode.Value
    | GotRequestToReview
    | GotRequestToGenerateSuppressionErrors
    | UserConfirmedFix Decode.Value
    | RequestedToKnowIfAFixConfirmationIsExpected


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
                        , abortWithDetails = abortWithDetails model.env model.options.supportsColor
                        }
                        storeMsg
                        model.store
            in
            startReviewIfNoPendingTasks
                ( { model | store = store }
                , Cmd.map StoreMsg cmd
                )

        SuppressedErrorsMsg suppressedErrorsMsg ->
            ( model
            , SuppressedErrors.update model.env.stdout suppressedErrorsMsg
            )

        FixPromptMsg fixPromptMsg ->
            case FixPrompt.update fixPromptMsg model.fixPrompt of
                FixPrompt.Accepted payload ->
                    applyFixChanges payload model

                FixPrompt.TriggerCmd cmd ->
                    ( model
                    , Cmd.map FixPromptMsg cmd
                    )

                FixPrompt.Refused ->
                    handleFixRefused model

                FixPrompt.Ignore ->
                    ( model, Cmd.none )

        AppliedFixes result ->
            -- TODO Do something?
            ( model, Cmd.none )


applyFixChanges : FixPromptPayload -> Model -> ( Model, Cmd Msg )
applyFixChanges { changedFiles, removedFiles } model =
    -- TODO
    --   - Pass files as part of payload
    -- From JS: askConfirmationToFixWithOptions
    --   - Format Elm files
    --   - Delete Elm files
    --   - Check if elm.json was modified
    --      - Refetch source-dependencies / dependencies if they changed
    -- From Elm: UserConfirmedFix confirmation ->
    --   - ???
    ( model
    , Task.map2 always
        (changedFiles
            -- TODO Format Elm files
            |> TaskExtra.mapAll (\{ filePath, source } -> Fs.writeTextFile model.fs filePath source)
        )
        (TaskExtra.mapAll (\filePath -> Fs.deleteFile model.fs filePath) removedFiles)
        |> Task.attempt AppliedFixes
    )


handleFixRefused : Model -> ( Model, Cmd Msg )
handleFixRefused model =
    let
        project : Project
        project =
            Store.project model.store
    in
    case model.errorAwaitingConfirmation of
        AwaitingError error ->
            { model
                | errorAwaitingConfirmation = NotAwaiting
                , fixAllResultProject = project
            }
                |> refuseError error
                |> runReview { fixesAllowed = True } (Store.project model.store)
                |> reportOrFix

        AwaitingFixAll ->
            { model
                | errorAwaitingConfirmation = NotAwaiting
                , fixAllResultProject = project
            }
                |> runReview { fixesAllowed = False } project
                |> makeReport (Store.suppressedErrors model.store)

        NotAwaiting ->
            -- Should not be possible?
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
                        newModel : Model
                        newModel =
                            { model | fixAllErrors = Dict.empty }
                                |> runReview { fixesAllowed = False } (Store.project model.store)
                    in
                    ( newModel
                    , Cmd.batch
                        [ newModel.reviewErrors
                            |> SuppressedErrors.fromReviewErrors
                            |> SuppressedErrors.write model.fs model.options []
                            |> Cmd.map SuppressedErrorsMsg

                        -- TODO Don't print in JSON report mode
                        , Cli.println model.env.stdout
                            ("I created suppressions files in "
                                ++ Color.toAnsi model.options.supportsColor Color.Orange (SuppressedErrors.suppressedFolder model.options)
                            )
                        , Cli.exit 0
                        ]
                    )

                else
                    let
                        ( modelWithReviewResults, newCmd ) =
                            { model | fixAllErrors = Dict.empty }
                                |> runReview { fixesAllowed = True } (Store.project model.store)
                                |> reportOrFix
                    in
                    -- TODO Update suppressions
                    ( modelWithReviewResults
                    , Cmd.batch [ cmd, newCmd ]
                    )

            Store.NotReady ->
                unchanged

            Store.Failure files ->
                -- TODO Write problem
                ( model
                , Cmd.batch
                    [ Cli.println model.env.stderr ("Could not find files " ++ String.join "," files)
                    , Cli.exit 1
                    ]
                )

    else
        unchanged


updateOld : MsgOld -> Model -> ( Model, Cmd MsgOld )
updateOld msg model =
    case msg of
        ReceivedFile value ->
            case Decode.decodeValue Elm.Review.File.decode value of
                Ok rawFile ->
                    case rawFile.ast of
                        Nothing ->
                            let
                                project : Project
                                project =
                                    Project.addModule { path = rawFile.path, source = rawFile.source } (Store.project model.store)
                            in
                            ( { model | store = Store.updateProject (Project.addModule { path = rawFile.path, source = rawFile.source }) model.store }
                            , Encode.object
                                [ ( "path", Encode.string rawFile.path )
                                , ( "cacheRequest", cacheFileRequest project rawFile.source )
                                ]
                                |> acknowledgeFileReceipt
                            )

                        Just ast ->
                            ( { model
                                | store =
                                    Store.updateProject
                                        (Project.addParsedModule
                                            { path = rawFile.path
                                            , source = rawFile.source
                                            , ast = ast
                                            }
                                        )
                                        model.store
                              }
                            , Encode.object
                                [ ( "path", Encode.string rawFile.path )
                                , ( "cacheRequest", Encode.null )
                                ]
                                |> acknowledgeFileReceipt
                            )

                Err err ->
                    ( model, abort model.env model.options.supportsColor (Decode.errorToString err) )

        RemovedFile path ->
            ( { model | store = Store.updateProject (Project.removeFile path) model.store }, Cmd.none )

        ReceivedElmJsonOld rawElmJson ->
            case Decode.decodeValue elmJsonDecoder rawElmJson of
                Ok elmJson ->
                    ( { model | store = Store.updateProject (Project.addElmJson elmJson) model.store }
                    , Cmd.none
                    )

                Err _ ->
                    ( model, Cmd.none )

        ReceivedReadmeOld rawReadme ->
            let
                readmeDecoder : Decode.Decoder { path : String, content : String }
                readmeDecoder =
                    Decode.map2 (\path content -> { path = path, content = content })
                        (Decode.field "path" Decode.string)
                        (Decode.field "content" Decode.string)
            in
            case Decode.decodeValue readmeDecoder rawReadme of
                Ok readme ->
                    ( { model | store = Store.updateProject (Project.addReadme readme) model.store }
                    , Cmd.none
                    )

                Err _ ->
                    ( model, Cmd.none )

        ReceivedExtraFiles rawFiles ->
            case Decode.decodeValue (Decode.dict Decode.string) rawFiles of
                Ok files ->
                    ( { model | store = Store.updateProject (Project.addExtraFiles files) model.store }
                    , Cmd.none
                    )

                Err _ ->
                    ( model, Cmd.none )

        ReceivedDependencies json ->
            case Decode.decodeValue (dependenciesDecoder model.options.ignoreProblematicDependencies) json of
                Err decodeError ->
                    ( model
                    , if String.contains "I need a valid module name like" (Decode.errorToString decodeError) then
                        abortWithDetails
                            model.env
                            model.options.supportsColor
                            { title = "FOUND PROBLEMATIC DEPENDENCIES"
                            , message =
                                """I encountered an error when reading the dependencies of the project. It seems due to dependencies with modules containing `_` in their names. Unfortunately, this is an error I have no control over and I am waiting in one of the libraries I depend on. What I propose you do, is to re-run elm-review like this:

    elm-review --ignore-problematic-dependencies

This will ignore the problematic dependencies, and can GIVE YOU INCORRECT RESULTS! This is a temporary measure.

If I am mistaken about the nature of the problem, please open a bug report at https://github.com/jfmengels/node-elm-review/issues:

"""
                                    ++ Decode.errorToString decodeError
                            }

                      else
                        abortWithDetails
                            model.env
                            model.options.supportsColor
                            { title = "PROBLEM READING DEPENDENCIES"
                            , message =
                                "I encountered an error when reading the dependencies of the project. I suggest opening a bug report at https://github.com/jfmengels/node-elm-review/issues."
                                    ++ Decode.errorToString decodeError
                            }
                    )

                Ok dependencies ->
                    ( { model
                        | store =
                            Store.updateProject
                                (\project ->
                                    List.foldl
                                        Project.addDependency
                                        (Project.removeDependencies project)
                                        dependencies
                                )
                                model.store
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
                    let
                        previousSuppressErrors : SuppressedErrors
                        previousSuppressErrors =
                            Store.suppressedErrors model.store
                    in
                    if suppressedErrors == previousSuppressErrors then
                        ( model, Cmd.none )

                    else
                        makeReport previousSuppressErrors
                            { model
                                | store = Store.setSuppressedErrors suppressedErrors model.store
                                , reviewErrorsAfterSuppression = SuppressedErrors.apply model.options.unsuppressMode suppressedErrors model.reviewErrors
                            }

        GotRequestToReview ->
            { model | fixAllErrors = Dict.empty }
                |> runReview { fixesAllowed = True } (Store.project model.store)
                |> reportOrFixOld

        GotRequestToGenerateSuppressionErrors ->
            let
                newModel : Model
                newModel =
                    { model | fixAllErrors = Dict.empty }
                        |> runReview { fixesAllowed = False } (Store.project model.store)
            in
            ( newModel
            , newModel.reviewErrors
                |> SuppressedErrors.fromReviewErrors
                |> SuppressedErrors.encode []
                |> suppressionsResponse
            )

        UserConfirmedFix confirmation ->
            case Decode.decodeValue (confirmationDecoder model.options.ignoreProblematicDependencies) confirmation of
                Ok (Accepted { rawFiles, dependencies }) ->
                    let
                        previousProject : Project
                        previousProject =
                            model.fixAllResultProject

                        newProject : Project
                        newProject =
                            List.foldl (\file acc -> addUpdatedFileToProject dependencies file acc) previousProject rawFiles
                    in
                    if List.length (Project.modulesThatFailedToParse newProject) > List.length (Project.modulesThatFailedToParse previousProject) then
                        -- There is a new file that failed to parse in the
                        -- project when we updated the fixed file. This means
                        -- that our fix introduced a syntactical regression that
                        -- we were not successful in preventing earlier.
                        ( model
                          -- TODO Improve abort message
                        , abort model.env model.options.supportsColor <| "One file among " ++ (String.join ", " <| List.map .path rawFiles) ++ " could not be read. An incorrect fix may have been introduced into one of these files..."
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
                            | store = Store.setProject newProject model.store
                            , rules = model.fixAllRules
                            , fixAllErrors = Dict.empty
                            , errorsHaveBeenFixedPreviously = True
                        }
                            |> runReview { fixesAllowed = True } newProject
                            |> reportOrFixOld
                            -- TODO Separate sending files to be cached and computing the files.
                            -- We may now already have found new fixes which are likely to be accepted.
                            |> Tuple.mapSecond
                                (\cmd ->
                                    (cmd :: List.map (.source >> sendFileToBeCached newProject) rawFiles)
                                        |> Cmd.batch
                                )

                Ok Refused ->
                    let
                        project : Project
                        project =
                            Store.project model.store
                    in
                    case model.errorAwaitingConfirmation of
                        AwaitingError error ->
                            { model
                                | errorAwaitingConfirmation = NotAwaiting
                                , fixAllResultProject = project
                            }
                                |> refuseError error
                                |> runReview { fixesAllowed = True } (Store.project model.store)
                                |> reportOrFixOld

                        AwaitingFixAll ->
                            { model
                                | errorAwaitingConfirmation = NotAwaiting
                                , fixAllResultProject = project
                            }
                                |> runReview { fixesAllowed = False } project
                                |> makeReport (Store.suppressedErrors model.store)

                        NotAwaiting ->
                            -- Should not be possible?
                            runReview { fixesAllowed = False } project model
                                |> makeReport (Store.suppressedErrors model.store)

                Err err ->
                    ( model, abort model.env model.options.supportsColor (Decode.errorToString err) )

        RequestedToKnowIfAFixConfirmationIsExpected ->
            ( model, fixConfirmationStatus (model.errorAwaitingConfirmation /= NotAwaiting) )


elmJsonDecoder : Decode.Decoder { path : String, raw : String, project : Elm.Project.Project }
elmJsonDecoder =
    Decode.map3 (\path raw project -> { path = path, raw = raw, project = project })
        (Decode.field "path" Decode.string)
        (Decode.field "raw" Decode.string)
        (Decode.field "project" Elm.Project.decoder)


dependenciesDecoder : Bool -> Decode.Decoder (List Dependency)
dependenciesDecoder ignoreProblematicDependencies =
    if ignoreProblematicDependencies then
        Decode.list
            (Decode.oneOf
                [ Decode.map Just dependencyDecoder
                , Decode.succeed Nothing
                ]
            )
            |> Decode.map (List.filterMap identity)

    else
        Decode.list dependencyDecoder


dependencyDecoder : Decode.Decoder Dependency
dependencyDecoder =
    Decode.map3 Dependency.create
        (Decode.field "name" Decode.string)
        (Decode.field "elmJson" Elm.Project.decoder)
        (Decode.field "docsJson" <| Decode.list Elm.Docs.decoder)


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
    = Accepted
        { rawFiles : List { path : String, source : String, ast : Maybe Elm.Syntax.File.File }
        , dependencies : Maybe (List Dependency)
        }
    | Refused


confirmationDecoder : Bool -> Decode.Decoder Confirmation
confirmationDecoder ignoreProblematicDependencies =
    Decode.field "answer" Decode.bool
        |> Decode.andThen
            (\accepted ->
                if accepted then
                    Decode.map2 (\rawFiles dependencies -> Accepted { rawFiles = rawFiles, dependencies = dependencies })
                        (Decode.field "files" (Decode.list Elm.Review.File.decode))
                        (Decode.field "dependencies" (dependenciesDecoder ignoreProblematicDependencies) |> Decode.maybe)

                else
                    Decode.succeed Refused
            )


runReview : { fixesAllowed : Bool } -> Project -> Model -> Model
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
    in
    { model
        | reviewErrors = errors
        , reviewErrorsAfterSuppression =
            errors
                |> CliCommunication.timerStart model.options.communicationKey "apply-suppressions"
                |> SuppressedErrors.apply model.options.unsuppressMode suppressedErrors
                |> CliCommunication.timerEnd model.options.communicationKey "apply-suppressions"
        , rules =
            if model.isInitialRun || model.options.fixMode == FixOptions.DontFix then
                rules

            else
                model.rules
        , isInitialRun = False
        , fixAllRules = rules
        , store =
            if model.options.fixMode == FixOptions.DontFix then
                Store.setProject project model.store

            else
                model.store
        , fixAllResultProject = project
        , fixAllErrors = fixedErrors
        , errorAwaitingConfirmation = NotAwaiting
        , extracts = extracts
    }


reportOrFixOld : Model -> ( Model, Cmd msg )
reportOrFixOld model =
    case model.options.fixMode of
        FixOptions.DontFix ->
            model
                |> CliCommunication.timerStart model.options.communicationKey "process-errors"
                |> makeReport (Store.suppressedErrors model.store)
                |> CliCommunication.timerEnd model.options.communicationKey "process-errors"

        FixOptions.Fix ->
            applyFixesAfterReviewOld model True model.options.fileRemovalFixesEnabled

        FixOptions.FixAll ->
            applyFixesAfterReviewOld model False model.options.fileRemovalFixesEnabled


reportOrFix : Model -> ( Model, Cmd Msg )
reportOrFix model =
    case model.options.fixMode of
        FixOptions.DontFix ->
            model
                |> CliCommunication.timerStart model.options.communicationKey "process-errors"
                |> makeReport (Store.suppressedErrors model.store)
                |> CliCommunication.timerEnd model.options.communicationKey "process-errors"

        FixOptions.Fix ->
            applyFixesAfterReview model True model.options.fileRemovalFixesEnabled

        FixOptions.FixAll ->
            applyFixesAfterReview model False model.options.fileRemovalFixesEnabled


makeReport : SuppressedErrors -> Model -> ( Model, Cmd msg )
makeReport previousSuppressedErrors model =
    let
        ( newModel, suppressedErrorsForJson ) =
            if List.isEmpty model.reviewErrorsAfterSuppression && model.options.writeSuppressionFiles then
                let
                    suppressedErrors : SuppressedErrors
                    suppressedErrors =
                        SuppressedErrors.fromReviewErrors model.reviewErrors
                in
                ( { model
                    | store = Store.setSuppressedErrors suppressedErrors model.store
                    , rules = model.fixAllRules
                  }
                  -- TODO Write suppression files
                , SuppressedErrors.encode (List.map Rule.ruleName model.rules) suppressedErrors
                )

            else
                ( { model | rules = model.fixAllRules }, Encode.null )

        newSuppressedErrors : SuppressedErrors
        newSuppressedErrors =
            Store.suppressedErrors newModel.store

        ruleLinks : Dict String String
        ruleLinks =
            Store.ruleLinks newModel.store
    in
    ( newModel
    , Cmd.batch
        [ case newModel.options.reportMode of
            HumanReadable ->
                let
                    filesWithError : List { path : Reporter.FilePath, source : Reporter.Source, errors : List Reporter.Error }
                    filesWithError =
                        groupErrorsByFile (fromReviewError newSuppressedErrors ruleLinks) (Store.project model.store) model.reviewErrorsAfterSuppression
                in
                Reporter.formatReport
                    newModel.options
                    { suppressedErrors = newSuppressedErrors
                    , originalNumberOfSuppressedErrors = SuppressedErrors.count previousSuppressedErrors
                    , errorsHaveBeenFixedPreviously = newModel.errorsHaveBeenFixedPreviously
                    }
                    filesWithError
                    |> Text.toAnsi model.options.supportsColor
                    |> Cli.println model.env.stdout

            Json ->
                let
                    errorsByFile : List { path : Reporter.FilePath, source : Reporter.Source, errors : List Rule.ReviewError }
                    errorsByFile =
                        groupErrorsByFile identity (Store.project model.store) model.reviewErrors

                    errors : Encode.Value
                    errors =
                        Encode.list
                            (encodeErrorByFile
                                model.options
                                { suppressedErrors = newSuppressedErrors
                                , reviewErrorsAfterSuppression = model.reviewErrorsAfterSuppression
                                }
                                ruleLinks
                            )
                            errorsByFile
                in
                printJson
                    model.env
                    model.options.debug
                    errors
                    (Encode.dict identity identity newModel.extracts)

            NDJson ->
                let
                    errorsByFile : List { path : Reporter.FilePath, source : Reporter.Source, errors : List Rule.ReviewError }
                    errorsByFile =
                        groupErrorsByFile identity (Store.project model.store) model.reviewErrors
                in
                errorsByFile
                    |> List.concatMap
                        (encodeErrorsForNDJson
                            newModel.options
                            { suppressedErrors = newSuppressedErrors
                            , reviewErrorsAfterSuppression = model.reviewErrorsAfterSuppression
                            }
                            ruleLinks
                        )
                    |> printNDJson model.env
        , if model.options.watch then
            Cmd.none

          else if List.isEmpty model.reviewErrorsAfterSuppression then
            Cli.exit 0

          else
            Cli.exit 1
        ]
    )


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


applyFixesAfterReviewOld : Model -> Bool -> Bool -> ( Model, Cmd msg )
applyFixesAfterReviewOld model allowPrintingSingleFix fileRemovalFixesEnabled =
    if Dict.isEmpty model.fixAllErrors then
        makeReport (Store.suppressedErrors model.store) model

    else
        case Project.diffV2 { before = Store.project model.store, after = model.fixAllResultProject } of
            [] ->
                makeReport (Store.suppressedErrors model.store) model

            diffs ->
                if allowPrintingSingleFix then
                    sendFixPromptOld fileRemovalFixesEnabled model diffs

                else
                    ( { model | errorAwaitingConfirmation = AwaitingFixAll }
                    , sendFixPromptForMultipleFixes fileRemovalFixesEnabled model diffs (countErrors model.fixAllErrors)
                    )


applyFixesAfterReview : Model -> Bool -> Bool -> ( Model, Cmd Msg )
applyFixesAfterReview model allowPrintingSingleFix fileRemovalFixesEnabled =
    if Dict.isEmpty model.fixAllErrors then
        makeReport (Store.suppressedErrors model.store) model

    else
        case Project.diffV2 { before = Store.project model.store, after = model.fixAllResultProject } of
            [] ->
                makeReport (Store.suppressedErrors model.store) model

            diffs ->
                if allowPrintingSingleFix then
                    sendFixPrompt fileRemovalFixesEnabled model diffs

                else
                    ( { model | errorAwaitingConfirmation = AwaitingFixAll }
                    , -- TODO Handle multiple fix prompt
                      sendFixPromptForMultipleFixes fileRemovalFixesEnabled model diffs (countErrors model.fixAllErrors)
                    )


sendFixPromptOld : Bool -> Model -> List FixedFile -> ( Model, Cmd msg )
sendFixPromptOld fileRemovalFixesEnabled model diffs =
    case numberOfErrors model.fixAllErrors of
        NoErrors ->
            ( model, Cmd.none )

        OneError filePath error ->
            let
                changedFiles : List { path : Reporter.FilePath, raw : String, source : Reporter.Source }
                changedFiles =
                    List.filterMap
                        (\{ path, diff } ->
                            case diff of
                                Project.Edited { after } ->
                                    Just
                                        { path = Reporter.FilePath path
                                        , raw = after
                                        , source = Reporter.Source (after |> String.lines |> Array.fromList)
                                        }

                                Project.Removed ->
                                    Nothing
                        )
                        diffs

                removedFiles : List String
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
            in
            ( { model | errorAwaitingConfirmation = AwaitingError error }
            , [ ( "confirmationMessage"
                , Reporter.formatSingleFixProposal
                    model.options
                    (pathAndSource (Store.project model.store) filePath)
                    (fromReviewError (Store.suppressedErrors model.store) (Store.ruleLinks model.store) error)
                    diffs
                    |> encodeReport
                )
              , ( "changedFiles", Encode.list encodeChangedFile changedFiles )
              , ( "removedFiles", Encode.list Encode.string removedFiles )
              , ( "count", Encode.int 1 )
              ]
                |> Encode.object
                |> askConfirmationToFix
            )

        MultipleErrors numberOfFixedErrors ->
            ( { model | errorAwaitingConfirmation = AwaitingFixAll }
            , sendFixPromptForMultipleFixes fileRemovalFixesEnabled model diffs numberOfFixedErrors
            )


sendFixPrompt : Bool -> Model -> List FixedFile -> ( Model, Cmd Msg )
sendFixPrompt fileRemovalFixesEnabled model diffs =
    case numberOfErrors model.fixAllErrors of
        NoErrors ->
            ( model, Cmd.none )

        OneError filePath error ->
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

                confirmationMessage : List Reporter.TextContent
                confirmationMessage =
                    Reporter.formatSingleFixProposal
                        model.options
                        (pathAndSource (Store.project model.store) filePath)
                        (fromReviewError (Store.suppressedErrors model.store) (Store.ruleLinks model.store) error)
                        diffs

                fixPayload : FixPromptPayload
                fixPayload =
                    { changedFiles = changedFiles
                    , removedFiles = removedFiles
                    }

                ( fixPrompt, fixPromptCmd ) =
                    case model.env.stdin of
                        Just stdin ->
                            confirmationMessage
                                |> Text.toAnsi model.options.supportsColor
                                |> FixPrompt.prompt stdin model.env.stdout model.fixPrompt fixPayload

                        Nothing ->
                            -- TODO
                            -- If there's no stdin, assume the reply is yes.
                            Debug.todo "Fix prompt without stdin"
            in
            ( { model
                | fixPrompt = fixPrompt
                , -- TODO Reuse/remove errorAwaitingConfirmation
                  errorAwaitingConfirmation = AwaitingError error
              }
            , Cmd.map FixPromptMsg fixPromptCmd
            )

        MultipleErrors numberOfFixedErrors ->
            ( { model | errorAwaitingConfirmation = AwaitingFixAll }
            , sendFixPromptForMultipleFixes fileRemovalFixesEnabled model diffs numberOfFixedErrors
            )


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


sendFixPromptForMultipleFixes : Bool -> Model -> List FixedFile -> Int -> Cmd msg
sendFixPromptForMultipleFixes fileRemovalFixesEnabled model diffs numberOfFixedErrors =
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
                model.fixAllErrors

        changedFiles : List { path : Reporter.FilePath, source : Reporter.Source }
        changedFiles =
            List.filterMap
                (\{ path, diff } ->
                    case diff of
                        Project.Edited { after } ->
                            Just
                                { path = Reporter.FilePath path
                                , source = Reporter.Source (after |> String.lines |> Array.fromList)
                                }

                        Project.Removed ->
                            Nothing
                )
                diffs

        removedFiles : List String
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

        confirmationMessage : Encode.Value
        confirmationMessage =
            Reporter.formatFixProposals fileRemovalFixesEnabled errorsForFile diffs
                |> encodeReport
    in
    askConfirmationToFix
        (Encode.object
            [ ( "confirmationMessage", confirmationMessage )
            , ( "changedFiles", Encode.list encodeChangedFile changedFiles )
            , ( "removedFiles", Encode.list Encode.string removedFiles )
            , ( "count", Encode.int numberOfFixedErrors )
            , ( "clearFixLine"
              , Encode.bool
                    (case model.options.fixMode of
                        FixOptions.DontFix ->
                            False

                        FixOptions.Fix ->
                            False

                        FixOptions.FixAll ->
                            True
                    )
              )
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


encodeChangedFile : { file | path : Reporter.FilePath, source : Reporter.Source } -> Encode.Value
encodeChangedFile changedFile =
    let
        (Reporter.Source source) =
            changedFile.source
    in
    Encode.object
        [ ( "path", encodeFilePath changedFile.path )
        , ( "source", Encode.string (source |> Array.toList |> String.join "\n") )
        ]


addUpdatedFileToProject : Maybe (List Dependency) -> { a | path : String, source : String } -> Project -> Project
addUpdatedFileToProject dependencies file project =
    if Just file.path == (Project.readme project |> Maybe.map .path) then
        Project.addReadme { path = file.path, content = file.source } project

    else if Just file.path == (Project.elmJson project |> Maybe.map .path) then
        updateElmJsonFile dependencies file project

    else
        Project.updateFile { path = file.path, source = file.source } project


updateElmJsonFile : Maybe (List Dependency) -> { a | source : String, path : String } -> Project -> Project
updateElmJsonFile dependencies file project =
    case Decode.decodeString Elm.Project.decoder file.source of
        Ok newElmJson ->
            let
                withUpdatedElmJson : Project
                withUpdatedElmJson =
                    Project.addElmJson
                        { path = file.path, raw = file.source, project = newElmJson }
                        project
            in
            case dependencies of
                Just deps ->
                    List.foldl
                        Project.addDependency
                        (Project.removeDependencies withUpdatedElmJson)
                        deps

                Nothing ->
                    -- If dependencies is Nothing, then the code in autofix.js
                    -- did not detect any change in the dependencies.
                    withUpdatedElmJson

        Err _ ->
            -- TODO Error
            project


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
                    |> maybeMapAndCons (\color_ -> ( "color", Encode.string (Color.toHex color_) )) color
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


subscriptions : Sub MsgOld
subscriptions =
    Sub.batch
        [ collectFile ReceivedFile
        , removeFile RemovedFile
        , collectElmJson ReceivedElmJsonOld
        , collectReadme ReceivedReadmeOld
        , collectExtraFiles ReceivedExtraFiles
        , collectDependencies ReceivedDependencies
        , updateSuppressedErrors UpdateSuppressedErrors
        , startReview (always GotRequestToReview)
        , startGeneratingSuppressions (always GotRequestToGenerateSuppressionErrors)
        , userConfirmedFix UserConfirmedFix
        , askForFixConfirmationStatus (always RequestedToKnowIfAFixConfirmationIsExpected)
        ]

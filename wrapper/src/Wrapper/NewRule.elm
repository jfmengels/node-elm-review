module Wrapper.NewRule exposing
    ( Model, init
    , Msg, update
    , ruleDescription, newSourceFile, newTestFile
    )

{-|

@docs Model, init
@docs Msg, update

@docs ruleDescription, newSourceFile, newTestFile

-}

import Capabilities exposing (Console, Stdin)
import Cli
import Elm.Module as Module
import Elm.Package
import Elm.Project
import Elm.Review.Vendor.List.Extra as ListExtra
import Elm.Version
import ElmReview.Color as Color exposing (Color(..), Colorize)
import ElmReview.Path as Path exposing (Path)
import ElmReview.Problem as Problem exposing (Problem)
import ElmReview.ReportMode as ReportMode
import ElmRun.FsExtra as FsExtra
import ElmRun.TaskExtra as TaskExtra
import Fs exposing (FileSystem, FsError)
import Json.Decode as Decode
import Json.Encode as Encode
import Platform exposing (Task)
import Regex exposing (Regex)
import Task
import Wrapper.Options exposing (NewRuleOptions)
import Wrapper.Options.RuleType as RuleType exposing (RuleType)


type Model
    = Model ModelData


type alias ModelData =
    { stdout : Console
    , stderr : Console
    , stdin : Maybe Stdin
    , fs : FileSystem
    , options : NewRuleOptions
    }


type Msg
    = GotElmJson (Result Problem Elm.Project.Project)
    | Done Module.Name (Result Problem (List Warning))


type alias Warning =
    Colorize -> String


readReviewElmJson : FileSystem -> Path -> Task Problem Elm.Project.Project
readReviewElmJson fs pathToElmJson_ =
    Fs.readTextFile fs pathToElmJson_
        |> Task.mapError
            (\error ->
                case error of
                    Fs.NotFound _ ->
                        Problem.from
                            { title = "COULD NOT FIND ELM.JSON"
                            , message = couldNotFindElmJsonMessage pathToElmJson_
                            }

                    Fs.PermissionDenied ->
                        Problem.from
                            { title = "PERMISSION DENIED"
                            , message = \c -> "I could not read " ++ c Yellow pathToElmJson_ ++ " file due to missing permissions."
                            }
                            |> Problem.withPath pathToElmJson_

                    Fs.IoError err ->
                        Problem.unexpectedError "when trying to read the elm.json file" err
                            |> Problem.withPath pathToElmJson_
            )
        |> Task.andThen
            (\elmJsonRaw ->
                Decode.decodeString Elm.Project.decoder elmJsonRaw
                    |> Result.mapError (\error -> Problem.invalidElmJson pathToElmJson_ error)
                    |> TaskExtra.resultToTask
            )


couldNotFindElmJsonMessage : Path -> Colorize -> String
couldNotFindElmJsonMessage pathToElmJson_ c =
    "I could not find a " ++ c Yellow pathToElmJson_ ++ """ file. I need you to be inside an Elm project.
                                               
You can run """ ++ c Cyan "elm-review new-package" ++ " to get started with a new project designed to publish review rules."


init : { env | stdout : Console, stderr : Console, stdin : Maybe Stdin } -> FileSystem -> NewRuleOptions -> ( Model, Cmd Msg )
init { stdout, stderr, stdin } fs options =
    let
        pathToElmJson_ : String
        pathToElmJson_ =
            pathToElmJson options
    in
    ( Model
        { stdout = stdout
        , stderr = stderr
        , stdin = stdin
        , fs = fs
        , options = options
        }
    , readReviewElmJson fs pathToElmJson_
        |> Task.attempt GotElmJson
    )


pathToElmJson : NewRuleOptions -> Path
pathToElmJson options =
    Path.join2 options.reviewFolder "elm.json"


validateOrElsePromptForRuleName : Elm.Project.Project -> Maybe String -> Model -> Cmd Msg
validateOrElsePromptForRuleName elmJson newRuleName ((Model { options }) as model) =
    case Maybe.andThen Module.fromString newRuleName of
        Just ruleName ->
            validateOrElsePromptForRuleType elmJson ruleName options.ruleType model

        Nothing ->
            promptForRuleName ()


validateOrElsePromptForRuleType : Elm.Project.Project -> Module.Name -> Maybe RuleType -> Model -> Cmd Msg
validateOrElsePromptForRuleType elmJson ruleName maybeRuleType model =
    case maybeRuleType of
        Just ruleType ->
            run elmJson ruleName ruleType model

        Nothing ->
            promptForRuleType ()


promptForRuleName : () -> Cmd Msg
promptForRuleName () =
    Debug.todo "promptForRuleName"


promptForRuleType : () -> Cmd Msg
promptForRuleType () =
    Debug.todo "promptForRuleType"


run : Elm.Project.Project -> Module.Name -> RuleType -> Model -> Cmd Msg
run elmJson ruleModuleName ruleType (Model { fs, options }) =
    let
        ruleName : String
        ruleName =
            Module.toString ruleModuleName

        ruleNameSegments : List String
        ruleNameSegments =
            String.split "." ruleName

        srcFilePath : Path
        srcFilePath =
            Path.join (options.reviewFolder :: "src" :: ruleNameSegments) ++ ".elm"

        testsFilePath : Path
        testsFilePath =
            Path.join (options.reviewFolder :: "tests" :: ruleNameSegments) ++ "Test.elm"
    in
    Task.map3 (\() () warnings -> warnings)
        (Fs.createDirectory fs (Path.dirname srcFilePath)
            |> Task.andThen (\() -> Fs.writeTextFile fs srcFilePath (newSourceFile elmJson ruleName ruleType))
            |> Task.mapError
                (\err ->
                    Problem.unexpectedError "while writing source file for new rule" (FsExtra.errorToString err)
                        |> Problem.withPath srcFilePath
                )
        )
        (Fs.createDirectory fs (Path.dirname testsFilePath)
            |> Task.andThen (\() -> Fs.writeTextFile fs testsFilePath (newTestFile ruleName))
            |> Task.mapError
                (\err ->
                    Problem.unexpectedError "while writing test file for new rule" (FsExtra.errorToString err)
                        |> Problem.withPath testsFilePath
                )
        )
        (case elmJson of
            Elm.Project.Application _ ->
                Task.succeed []

            Elm.Project.Package pkg ->
                if String.contains "/elm-review-" (Elm.Package.toString pkg.name) then
                    Task.map3 (\() w1 w2 -> List.append w1 w2)
                        (exposeRuleAsPartOfElmReviewPackage fs (pathToElmJson options) pkg ruleModuleName)
                        (injectRuleInReadme fs options pkg ruleName)
                        (injectRuleInPreviewFolders fs options.reviewFolder pkg ruleName)

                else
                    Task.succeed []
        )
        |> Task.attempt (Done ruleModuleName)


newSourceFile : Elm.Project.Project -> String -> RuleType -> String
newSourceFile elmJson ruleName ruleType =
    let
        tryItOutSection : String
        tryItOutSection =
            case elmJson of
                Elm.Project.Application _ ->
                    ""

                Elm.Project.Package { name } ->
                    """


## Try it out

You can try this rule out by running the following command:

```bash
elm-review --template """ ++ Elm.Package.toString name ++ "/example --rules " ++ ruleName ++ "\n```"

        ruleTemplate : String
        ruleTemplate =
            case ruleType of
                RuleType.ModuleRule ->
                    moduleRuleTemplate ruleName

                RuleType.ProjectRule ->
                    projectRuleTemplate ruleName
    in
    "module " ++ ruleName ++ """ exposing (rule)

{-|

@docs rule

-}

import Elm.Syntax.Expression exposing (Expression)
import Elm.Syntax.Node as Node exposing (Node)
import Review.Rule as Rule exposing (Rule)


{-| Reports... REPLACEME

    config =
        [ """ ++ ruleName ++ """.rule
        ]


## Fail

    a =
        "REPLACEME example to replace"


## Success

    a =
        "REPLACEME example to replace"


## When (not) to enable this rule

This rule is useful when REPLACEME.
This rule is not useful when REPLACEME.""" ++ tryItOutSection ++ """

-}""" ++ ruleTemplate


moduleRuleTemplate : String -> String
moduleRuleTemplate ruleName =
    """
rule : Rule
rule =
    Rule.newModuleRuleSchemaUsingContextCreator \"""" ++ ruleName ++ """" initialContext
        |> Rule.withExpressionEnterVisitor expressionVisitor
        |> Rule.fromModuleRuleSchema


type alias Context =
    {}


initialContext : Rule.ContextCreator () Context
initialContext =
    Rule.initContextCreator
        (\\() ->
            {}
        )


expressionVisitor : Node Expression -> Context -> ( List (Rule.Error {}), Context )
expressionVisitor node context =
    case Node.value node of
        _ ->
            ( [], context )
"""


projectRuleTemplate : String -> String
projectRuleTemplate ruleName =
    """
rule : Rule
rule =
    Rule.newProjectRuleSchema \"""" ++ ruleName ++ """" initialProjectContext
        |> Rule.withModuleVisitor moduleVisitor
        |> Rule.withModuleContextUsingContextCreator
            { fromProjectToModule = fromProjectToModule
            , fromModuleToProject = fromModuleToProject
            , foldProjectContexts = foldProjectContexts
            }
        -- Enable this if modules need to get information from other modules
        -- |> Rule.withContextFromImportedModules
        |> Rule.fromProjectRuleSchema


type alias ProjectContext =
    {}


type alias ModuleContext =
    {}


moduleVisitor : Rule.ModuleRuleSchema schema ModuleContext -> Rule.ModuleRuleSchema { schema | hasAtLeastOneVisitor : () } ModuleContext
moduleVisitor schema =
    schema
        |> Rule.withExpressionEnterVisitor expressionVisitor


initialProjectContext : ProjectContext
initialProjectContext =
    {}


fromProjectToModule : Rule.ContextCreator ProjectContext ModuleContext
fromProjectToModule =
    Rule.initContextCreator
        (\\projectContext ->
            {}
        )


fromModuleToProject : Rule.ContextCreator ModuleContext ProjectContext
fromModuleToProject =
    Rule.initContextCreator
        (\\moduleContext ->
            {}
        )


foldProjectContexts : ProjectContext -> ProjectContext -> ProjectContext
foldProjectContexts new previous =
    {}


expressionVisitor : Node Expression -> ModuleContext -> ( List (Rule.Error {}), ModuleContext )
expressionVisitor node context =
    case Node.value node of
        _ ->
            ( [], context )
"""


newTestFile : String -> String
newTestFile ruleName =
    "module " ++ ruleName ++ """Test exposing (all)

import """ ++ ruleName ++ """ exposing (rule)
import Review.Test
import Test exposing (Test, describe, test)


all : Test
all =
    describe \"""" ++ ruleName ++ """"
        [ test "should not report an error when REPLACEME" <|
            \\() ->
                \"\"\"module A exposing (..)
a = 1
\"\"\"
                    |> Review.Test.run rule
                    |> Review.Test.expectNoErrors
        , test "should report an error when REPLACEME" <|
            \\() ->
                \"\"\"module A exposing (..)
a = 1
\"\"\"
                    |> Review.Test.run rule
                    |> Review.Test.expectErrors
                        [ Review.Test.error
                            { message = "REPLACEME"
                            , details = [ "REPLACEME" ]
                            , under = "REPLACEME"
                            }
                        ]
        ]
"""


exposeRuleAsPartOfElmReviewPackage : FileSystem -> Path -> Elm.Project.PackageInfo -> Module.Name -> Task Problem ()
exposeRuleAsPartOfElmReviewPackage fs elmJsonPath pkg ruleModuleName =
    case computeExposedModules ruleModuleName pkg.exposed of
        Just exposed ->
            { pkg | exposed = exposed }
                |> Elm.Project.Package
                |> Elm.Project.encode
                |> Encode.encode 4
                |> Fs.writeTextFile fs elmJsonPath
                |> Task.mapError
                    (\err ->
                        Problem.unexpectedError "while adding the new rule to elm.json's \"exposed-modules\"" (FsExtra.errorToString err)
                            |> Problem.withPath elmJsonPath
                    )

        Nothing ->
            Task.succeed ()


computeExposedModules : Module.Name -> Elm.Project.Exposed -> Maybe Elm.Project.Exposed
computeExposedModules ruleModuleName exposed =
    case exposed of
        Elm.Project.ExposedList exposedModules ->
            if List.any (\mod -> ruleModuleName == mod) exposedModules then
                Nothing

            else
                (ruleModuleName :: exposedModules)
                    |> List.sortBy Module.toString
                    |> Elm.Project.ExposedList
                    |> Just

        Elm.Project.ExposedDict sections ->
            if List.any (\( _, exposedModules ) -> List.any (\mod -> ruleModuleName == mod) exposedModules) sections then
                Nothing

            else
                case sections of
                    [] ->
                        [ ruleModuleName ]
                            |> Elm.Project.ExposedList
                            |> Just

                    ( sectionTitle, exposedModules ) :: restOfSections ->
                        let
                            updatedSection : ( String, List Module.Name )
                            updatedSection =
                                ( sectionTitle
                                , (ruleModuleName :: exposedModules)
                                    |> List.sortBy Module.toString
                                )
                        in
                        (updatedSection :: restOfSections)
                            |> Elm.Project.ExposedDict
                            |> Just


injectRuleInReadme : FileSystem -> NewRuleOptions -> Elm.Project.PackageInfo -> String -> Task Problem (List Warning)
injectRuleInReadme fs options pkg ruleName =
    let
        readmePath : Path
        readmePath =
            Path.join2 options.reviewFolder "README.md"
    in
    Fs.readTextFile fs readmePath
        |> TaskExtra.toResultTask
        |> Task.andThen
            (\readmeFileRead ->
                case readmeFileRead of
                    Ok readmeContent ->
                        let
                            { lines, warnings } =
                                injectRuleInReadmeContent pkg ruleName readmeContent
                        in
                        lines
                            |> String.join "\n"
                            |> Fs.writeTextFile fs readmePath
                            |> Task.mapError
                                (\err ->
                                    Problem.unexpectedError "while adding the new rule to the README" (FsExtra.errorToString err)
                                        |> Problem.withPath readmePath
                                )
                            |> Task.map (\() -> warnings)

                    Err () ->
                        Task.succeed [ \c -> "I tried mentioning the rule in README.md but could not find a " ++ c Yellow "README.md" ++ " file." ]
            )


injectRuleInReadmeContent : Elm.Project.PackageInfo -> String -> String -> FileModification
injectRuleInReadmeContent pkg ruleName content =
    { lines = String.split "\n" content
    , warnings = []
    }
        |> insertRuleDescription pkg ruleName
        |> insertRuleInConfiguration "README.md" pkg ruleName


type alias FileModification =
    { lines : List String
    , warnings : List Warning
    }


updateLines : FileModification -> List String -> FileModification
updateLines { warnings } lines =
    { lines = lines
    , warnings = warnings
    }


addWarning : FileModification -> Warning -> FileModification
addWarning { lines, warnings } warning =
    { lines = lines
    , warnings = warning :: warnings
    }


insertRuleDescription : Elm.Project.PackageInfo -> String -> FileModification -> FileModification
insertRuleDescription pkg ruleName fileModification =
    case ListExtra.findIndex containsRuleSection fileModification.lines of
        Just rulesSectionIndex ->
            let
                linesAfter : List String
                linesAfter =
                    List.drop (rulesSectionIndex + 2) fileModification.lines
            in
            if alreadyHasRuleDescription ruleName linesAfter then
                fileModification

            else
                (List.take (rulesSectionIndex + 2) fileModification.lines
                    ++ ruleDescription (Elm.Package.toString pkg.name) (Elm.Version.toString pkg.version) ruleName
                    :: linesAfter
                )
                    |> updateLines fileModification

        Nothing ->
            addWarning fileModification
                (\c -> "I tried mentioning the rule in the " ++ c Yellow "Provided rules" ++ " section of the README.md but could not find the section.")


containsRuleSection : String -> Bool
containsRuleSection line =
    Regex.contains ruleSectionRegex line


ruleSectionRegex : Regex
ruleSectionRegex =
    Regex.fromStringWith { caseInsensitive = True, multiline = False } "^#+.*rules"
        |> Maybe.withDefault Regex.never


alreadyHasRuleDescription : String -> List String -> Bool
alreadyHasRuleDescription ruleName linesAfter =
    let
        textToSearchFor : String
        textToSearchFor =
            "- [`" ++ ruleName ++ "`](https://package.elm-lang.org/packages"
    in
    linesUntilNextSection linesAfter
        |> List.any (\line -> String.startsWith textToSearchFor line)


linesUntilNextSection : List String -> List String
linesUntilNextSection linesAfter =
    case ListExtra.findIndex (\line -> String.startsWith "#" line) linesAfter of
        Nothing ->
            linesAfter

        Just nextSectionIndex ->
            List.take (nextSectionIndex + 1) linesAfter


ruleDescription : String -> String -> String -> String
ruleDescription packageName packageVersion ruleName =
    let
        ruleNameAsUrl : String
        ruleNameAsUrl =
            String.replace ruleName "." "-"
    in
    "- [`" ++ ruleName ++ "`](https://package.elm-lang.org/packages/" ++ packageName ++ "/" ++ packageVersion ++ "/" ++ ruleNameAsUrl ++ ") - Reports REPLACEME."


injectRuleInPreviewFolders : FileSystem -> Path -> Elm.Project.PackageInfo -> String -> Task Problem (List Warning)
injectRuleInPreviewFolders fs reviewFolder pkg ruleName =
    Fs.walkTree fs reviewFolder (Just "elm.json") Fs.Any
        |> Task.mapError (\error -> Problem.unexpectedError "while searching for preview folders" (FsExtra.errorToString error))
        |> Task.andThen
            (\( files, _ ) ->
                files
                    |> List.filter
                        (\filePath ->
                            String.startsWith "./preview" filePath
                                && not (String.contains "/elm-stuff/" filePath)
                        )
                    |> List.map
                        (\filePath ->
                            injectRuleInPreview fs (Path.dirname (Path.join2 reviewFolder filePath)) pkg ruleName
                        )
                    |> Task.sequence
                    |> Task.map List.concat
            )


injectRuleInPreview : FileSystem -> Path -> Elm.Project.PackageInfo -> String -> Task Problem (List Warning)
injectRuleInPreview fs previewFolder pkg ruleName =
    let
        filePath : Path
        filePath =
            Path.join [ previewFolder, "src", "ReviewConfig.elm" ]
    in
    Fs.readTextFile fs filePath
        |> TaskExtra.toResultTask
        |> Task.andThen
            (\maybeContent ->
                case maybeContent of
                    Err () ->
                        Task.succeed [ \c -> "I tried inserting the rule in the " ++ c Yellow (previewFolder ++ "/") ++ " preview configuration but could not read it." ]

                    Ok content ->
                        let
                            result : FileModification
                            result =
                                insertRuleInConfiguration "README.md"
                                    pkg
                                    ruleName
                                    { lines = String.lines content
                                    , warnings = []
                                    }
                        in
                        if List.isEmpty result.warnings then
                            Fs.writeTextFile fs filePath (String.join "\n" result.lines)
                                |> Task.mapError
                                    (\error ->
                                        Problem.unexpectedError ("while trying to update the " ++ previewFolder ++ "/ preview configuration") (FsExtra.errorToString error)
                                            |> Problem.withPath filePath
                                    )
                                |> Task.map (\_ -> [])

                        else
                            Task.succeed [ \c -> "I tried inserting the rule in the " ++ c Yellow (previewFolder ++ "/") ++ " preview configuration but could not read it." ]
            )


insertRuleInConfiguration : String -> Elm.Project.PackageInfo -> String -> FileModification -> FileModification
insertRuleInConfiguration target pkg ruleName fileModification =
    if fileModification.lines |> String.join "\n" |> String.contains ("import " ++ ruleName ++ "\n") then
        -- Rule already exists in configuration
        { lines = fileModification.lines, warnings = [] }

    else
        case findSomeRuleName pkg.exposed of
            Just someRuleName ->
                fileModification
                    |> insertImport target ruleName
                    |> insertRuleInConfigList target ruleName someRuleName

            Nothing ->
                { lines = fileModification.lines
                , warnings = [ \c -> "I tried mentioning the rule in the configuration in " ++ c Yellow target ++ " but I could somehow not find where to insert it." ]
                }


findSomeRuleName : Elm.Project.Exposed -> Maybe String
findSomeRuleName exposed =
    case exposed of
        Elm.Project.ExposedList (ruleName :: _) ->
            Just (Module.toString ruleName)

        Elm.Project.ExposedDict (( _, ruleName :: _ ) :: _) ->
            Just (Module.toString ruleName)

        _ ->
            Nothing


insertImport : String -> String -> FileModification -> FileModification
insertImport target ruleName fileModification =
    case ListExtra.findIndex (\line -> String.startsWith "import" line) fileModification.lines of
        Nothing ->
            addWarning fileModification
                (\c -> "I tried adding an import to " ++ ruleName ++ " in the configuration of " ++ c Yellow target ++ " but could not find where to insert it.")

        Just firstImportIndex ->
            let
                linesBeforeFirstImport : List String
                linesBeforeFirstImport =
                    List.take firstImportIndex fileModification.lines

                linesAfterFirstImport : List String
                linesAfterFirstImport =
                    List.drop firstImportIndex fileModification.lines

                ( existingImportLines, linesAfterAllImports ) =
                    findExistingImports linesAfterFirstImport []

                imports : List String
                imports =
                    List.sort (("import " ++ ruleName) :: existingImportLines)
            in
            (linesBeforeFirstImport
                ++ imports
                ++ linesAfterAllImports
            )
                |> updateLines fileModification


findExistingImports : List String -> List String -> ( List String, List String )
findExistingImports lines acc =
    case lines of
        [] ->
            ( acc, [] )

        line :: rest ->
            if String.startsWith "import " line then
                findExistingImports rest (line :: acc)

            else
                ( acc, lines )


insertRuleInConfigList : String -> String -> String -> FileModification -> FileModification
insertRuleInConfigList target ruleName someRuleName fileModification =
    case ListExtra.findWithIndex (\line -> String.contains (someRuleName ++ ".rule") line) fileModification.lines of
        Nothing ->
            addWarning fileModification
                (\c -> "I tried adding an example of the rule configuration " ++ ruleName ++ " in the configuration of " ++ c Yellow target ++ " but could not find where to insert it.")

        Just ( line, lineIndex ) ->
            updateLines fileModification
                (if String.startsWith "[" (String.trimLeft line) then
                    List.take (lineIndex + 1) fileModification.lines
                        ++ ("    , " ++ ruleName ++ ".rule")
                        :: List.drop (lineIndex + 1) fileModification.lines

                 else
                    List.take lineIndex fileModification.lines
                        ++ ("    , " ++ ruleName ++ ".rule")
                        :: List.drop lineIndex fileModification.lines
                )


update : Msg -> Model -> Cmd Msg
update msg (Model model) =
    case msg of
        GotElmJson (Ok elmJson) ->
            validateOrElsePromptForRuleName elmJson model.options.newRuleName (Model model)

        GotElmJson (Err problem) ->
            Problem.exit model.stderr
                { color = model.options.color
                , reportMode = ReportMode.HumanReadable
                , debug = model.options.debug
                }
                problem

        Done ruleName (Ok warnings) ->
            let
                successMessage : String
                successMessage =
                    "Added rule " ++ Module.toString ruleName

                warningsMessage : String
                warningsMessage =
                    if List.isEmpty warnings then
                        ""

                    else
                        let
                            c : Colorize
                            c =
                                Color.toAnsi model.options.color
                        in
                        "\n\nI have however failed to apply some changes I wanted to make:\n\n"
                            ++ (List.map (\warning -> warning c) warnings
                                    |> String.join "\n\n"
                               )
            in
            Cmd.batch
                [ Cli.println model.stdout (successMessage ++ "!" ++ warningsMessage)
                , Cli.exit 0
                ]

        Done _ (Err problem) ->
            Problem.exit model.stderr
                { color = model.options.color
                , reportMode = ReportMode.HumanReadable
                , debug = model.options.debug
                }
                problem

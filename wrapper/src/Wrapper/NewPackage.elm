module Wrapper.NewPackage exposing
    ( Model, init
    , Msg, update
    )

{-|

@docs Model, init
@docs Msg, update

-}

import Elm.Constraint
import Elm.License as License exposing (License)
import Elm.Module as Module
import Elm.Package
import Elm.Project
import Elm.Review.CliVersion as CliVersion
import Elm.Review.ElmBinary as ElmBinary
import Elm.Review.Testable.Cli as Cli
import Elm.Review.Testable.Fs as Fs
import Elm.Review.Testable.FsData as FsData
import Elm.Review.Testable.Internal exposing (TCmd)
import Elm.Review.Testable.Stdin as Stdin
import Elm.Review.Testable.TTask as TTask exposing (TTask)
import Elm.Version as Version
import ElmReview.Color as Color exposing (Color(..), Colorize)
import ElmReview.Path as Path exposing (Path)
import ElmReview.Problem as Problem exposing (Problem)
import ElmReview.ReportMode as ReportMode
import Json.Encode as Encode
import Wrapper.MinVersion as MinVersion
import Wrapper.NewRule as NewRule
import Wrapper.Options exposing (NewPackageOptions)
import Wrapper.Options.RuleType exposing (RuleType)
import Wrapper.ReviewConfigTemplate as ReviewConfigTemplate


type Model
    = Model ModelData


type alias ModelData =
    { stdinSupported : Bool
    , options : NewPackageOptions
    }


type Msg
    = Done (Result Problem.Exit ())
    | PrintedNowExit Int


type alias Warning =
    Colorize -> String


init : NewPackageOptions -> TCmd Msg
init options =
    TTask.map2
        (\{ name, path } ( ruleName, ruleType ) ->
            { name = name
            , path = path
            , ruleName = ruleName
            , ruleType = ruleType
            }
        )
        promptForName
        -- TODO Use prefilled answers for tests
        (NewRule.prompts { newRuleName = Nothing, ruleType = Nothing })
        |> TTask.andThen (createProject options)
        |> TTask.andThen (\() -> Cli.printlnStdoutTask (successMessage (Color.toAnsi options.color)))
        |> TTask.onError (\problem -> Problem.exitOnUnrecoverable (formatOptions options) problem)
        |> TTask.attempt Done


promptForName : TTask Problem { name : Elm.Package.Name, path : String }
promptForName =
    promptForAuthorName
        |> TTask.andThen promptForPackageName


promptForAuthorName : TTask Problem String
promptForAuthorName =
    -- TODO Put special effects on prompt messages
    Cli.printlnStdoutTask """? Your GitHub username:"""
        |> TTask.andThen (\() -> Stdin.readLine)
        |> TTask.map String.trim
        |> TTask.mapError (Stdin.toProblem "while prompting for the GitHub username")
        |> TTask.andThen
            (\author ->
                if String.isEmpty author then
                    Cli.printlnStdoutTask "The GitHub username should not be empty."
                        |> TTask.andThen (\() -> promptForAuthorName)

                else
                    TTask.succeed author
            )


promptForPackageName : String -> TTask Problem { name : Elm.Package.Name, path : String }
promptForPackageName author =
    -- TODO Put special effects on prompt messages
    Cli.printlnStdoutTask """? The package name (starting with "elm-review-")"""
        |> TTask.andThen (\() -> Stdin.readLine)
        |> TTask.mapError (Stdin.toProblem "while prompting for the package name")
        |> TTask.map String.trim
        |> TTask.andThen
            (\package ->
                let
                    name : Maybe Elm.Package.Name
                    name =
                        if not (String.startsWith "elm-review-" package) then
                            Nothing

                        else
                            Elm.Package.fromString (author ++ "/" ++ package)
                in
                case name of
                    Just validName ->
                        TTask.succeed
                            { name = validName
                            , path = package
                            }

                    Nothing ->
                        Cli.printlnStdoutTask """The package name needs to start with "elm-review-"."""
                            |> TTask.andThen (\() -> promptForPackageName author)
            )


update : Msg -> TCmd Msg
update msg =
    case msg of
        Done result ->
            case result of
                Ok () ->
                    Cli.exit 0

                Err exit ->
                    Problem.exit exit

        PrintedNowExit exitCode ->
            Cli.exit exitCode


formatOptions : NewPackageOptions -> Problem.FormatOptions {}
formatOptions options =
    { color = options.color
    , reportMode = ReportMode.HumanReadable
    , debug = options.debug
    , attemptFutureRecovery = False
    }


type alias Input =
    { name : Elm.Package.Name
    , path : Path
    , ruleName : Module.Name
    , ruleType : RuleType
    }


createProject : NewPackageOptions -> Input -> TTask Problem ()
createProject options ({ name, path, ruleName, ruleType } as input) =
    let
        elmJson : Elm.Project.Project
        elmJson =
            createElmJson ruleName name

        ruleNameAsString : String
        ruleNameAsString =
            Module.toString ruleName
    in
    TTask.sequence
        [ -- Rule source file
          Fs.createFileAndItsDirectory
            (Path.join [ path, "src", String.replace "." "/" ruleNameAsString ++ ".elm" ])
            (NewRule.newSourceFile elmJson ruleNameAsString ruleType)
            |> TTask.mapError (\error -> Problem.unexpectedError "while creating the new rule's source file" (FsData.errorToString error))
        , -- Rule test file
          Fs.createFileAndItsDirectory
            (Path.join [ path, "tests", String.replace "." "/" ruleNameAsString ++ "Test.elm" ])
            (NewRule.newTestFile ruleNameAsString)
            |> TTask.mapError (\error -> Problem.unexpectedError "while creating the new rule's test file" (FsData.errorToString error))
        , -- elm.json
          createElmJsonFile elmJson path
        , -- package.json
          createPackageJsonFile name path
        , -- elm-tooling.json
          createElmToolingJson path
        , -- README.md
          createReadme input
        , -- preview/
          ElmBinary.findElmVersion
            |> TTask.andThen (\elmVersion -> ReviewConfigTemplate.create elmVersion (Path.join2 path "preview") (Just ruleNameAsString))
            |> TTask.mapError (\error -> Problem.unexpectedError "while creating the preview folder's configuration" (FsData.errorToString error))
        , -- .gitignore
          Fs.writeTextFile (Path.join2 path ".gitignore") (gitIgnore ())
            |> TTask.mapError (\error -> Problem.unexpectedError "while creating the new package's .gitignore file" (FsData.errorToString error))
        , -- GitHub actions and issue template
          -- TODO Use write instead of copy?
          Fs.createDirectory (Path.join2 path ".github/ISSUE_TEMPLATE/")
            |> TTask.mapError (\error -> Problem.unexpectedError "while creating the .github/ISSUE_TEMPLATE folder" (FsData.errorToString error))
        , Fs.createDirectory (Path.join2 path ".github/workflows/")
            |> TTask.mapError (\error -> Problem.unexpectedError "while creating the .github/workflows folder" (FsData.errorToString error))
        , Fs.copyDirectory
            { from = Path.join2 options.binaryRoot "new-package/github"
            , to = Path.join2 path ".github/"
            }
            |> TTask.mapError
                (\error -> Problem.unexpectedError "while copying the GitHub Actions" (FsData.errorToString error))

        -- TODO Add remaining new-package tasks
        --, createElmReviewConfiguration  input
        --, createLicense  input
        --, createMaintenanceScripts  input
        --, createPackageTests  input
        --, createCheckPreviewCompile  input
        ]


createElmJsonFile : Elm.Project.Project -> Path -> TTask Problem ()
createElmJsonFile elmJson packageNamePath =
    let
        packageElmJson : String
        packageElmJson =
            elmJson
                |> Elm.Project.encode
                |> Encode.encode 4
    in
    Fs.writeTextFile (Path.join2 packageNamePath "elm.json") packageElmJson
        |> TTask.mapError (\error -> Problem.unexpectedError "while creating the new package's elm.json file" (FsData.errorToString error))


createElmJson : Module.Name -> Elm.Package.Name -> Elm.Project.Project
createElmJson ruleName name =
    Elm.Project.Package
        { name = name
        , summary = ""
        , license = License.bsd3
        , version = Version.one
        , exposed = Elm.Project.ExposedList [ ruleName ]
        , deps = toElmJsonDeps dependencies
        , testDeps = toElmJsonDeps testDependencies
        , elm = elm019 ()
        }


dependencies : List ( String, String )
dependencies =
    [ ( "elm/core", "1.0.5 <= v < 2.0.0" )
    , ( "jfmengels/elm-review", MinVersion.supportedRange )
    , ( "stil4m/elm-syntax", "7.3.9 <= v < 8.0.0" )
    ]


testDependencies : List ( String, String )
testDependencies =
    [ ( "elm-explorations/test", "2.2.1 <= v < 3.0.0" )
    ]


elm019 : () -> Elm.Constraint.Constraint
elm019 () =
    case Elm.Constraint.fromString "0.19.0 <= v < 0.20.0" of
        Just constraint ->
            constraint

        Nothing ->
            elm019 ()


toElmJsonDeps : List ( String, String ) -> List ( Elm.Package.Name, Elm.Constraint.Constraint )
toElmJsonDeps deps =
    List.filterMap
        (\( pkg, constraint ) ->
            Maybe.map2 Tuple.pair
                (Elm.Package.fromString pkg)
                (Elm.Constraint.fromString constraint)
        )
        deps


createPackageJsonFile : Elm.Package.Name -> Path -> TTask Problem ()
createPackageJsonFile name path =
    let
        packageElmJson : String
        packageElmJson =
            packageJson name
                |> Encode.encode 4
    in
    Fs.writeTextFile (Path.join2 path "package.json") packageElmJson
        |> TTask.mapError (\error -> Problem.unexpectedError "while creating the new package's package.json file" (FsData.errorToString error))


packageJson : Elm.Package.Name -> Encode.Value
packageJson name =
    Encode.object
        [ ( "name", Encode.string <| Elm.Package.toString name )
        , ( "private", Encode.bool True )
        , ( "scripts", Encode.object (scripts ()) )
        , ( "engines", Encode.object [ ( "node", Encode.string ">=14.21.3" ) ] )
        , ( "devDependencies", Encode.object (packageJsonDevDependencies ()) )
        ]


scripts : () -> List ( String, Encode.Value )
scripts () =
    [ ( "test", "npm-run-all --print-name --silent --sequential test:make test:format test:run test:review test:package" )
    , ( "test:make", "elm make --docs=docs.json" )
    , ( "test:format", "elm-format src/ preview*/ tests/ --validate" )
    , ( "test:run", "elm-test" )
    , ( "test:review", "elm-review" )
    , ( "test:package", "node elm-review-package-tests/check-previews-compile.js" )
    , ( "preview-docs", "elm-doc-preview" )
    , ( "elm-bump", "npm-run-all --print-name --silent --sequential test bump-version 'test:review -- --fix-all-without-prompt' update-examples" )
    , ( "bump-version", "(yes | elm bump)" )
    , ( "update-examples", "node maintenance/update-examples-from-preview.js" )
    , ( "postinstall", "elm-tooling install" )
    ]
        |> List.map (\( name, script ) -> ( name, Encode.string script ))


packageJsonDevDependencies : () -> List ( String, Encode.Value )
packageJsonDevDependencies () =
    [ ( "elm-doc-preview", "^5.0.5" )
    , ( "elm-review", "^" ++ CliVersion.version )
    , ( "elm-test", "^0.19.1-revision17" )
    , ( "elm-tooling", "^1.17.0" )
    , ( "-extra", "^9.0.0" )
    , ( "npm-run-all", "^4.1.5" )
    , ( "tinyglobby", "^0.2.16" )
    ]
        |> List.map (\( name, script ) -> ( name, Encode.string script ))


createElmToolingJson : Path -> TTask Problem ()
createElmToolingJson path =
    let
        elmToolingJson : String
        elmToolingJson =
            Encode.object
                [ ( "tools"
                  , Encode.object
                        [ ( "elm", Encode.string "0.19.1" )
                        , ( "elm-format", Encode.string "0.8.8" )
                        , ( "elm-json", Encode.string "0.2.13" )
                        ]
                  )
                ]
                |> Encode.encode 4
    in
    Fs.writeTextFile (Path.join2 path "elm-tooling.json") elmToolingJson
        |> TTask.mapError (\error -> Problem.unexpectedError "while creating the new package's elm-tooling.json file" (FsData.errorToString error))


createReadme : Input -> TTask Problem ()
createReadme input =
    Fs.writeTextFile (Path.join2 input.path "README.md") (readme input)
        |> TTask.mapError (\error -> Problem.unexpectedError "while creating the new package's README file" (FsData.errorToString error))


readme : Input -> String
readme input =
    let
        fullName : String
        fullName =
            Elm.Package.toString input.name

        ruleName : String
        ruleName =
            Module.toString input.ruleName
    in
    "# " ++ fullName ++ """

Provides [`elm-review`](https://package.elm-lang.org/packages/jfmengels/elm-review/latest/) rules to REPLACEME.

## Provided rules

""" ++ NewRule.ruleDescription fullName "1.0.0" ruleName ++ """

## Configuration

```elm
module ReviewConfig exposing (config)

import """ ++ ruleName ++ """
import Review.Rule exposing (Rule)

config : List Rule
config =
    [ """ ++ ruleName ++ """.rule
    ]
```

## Try it out

You can try the example configuration above out by running the following command:

```bash
elm-review --template """ ++ fullName ++ """/example
```
"""


gitIgnore : () -> String
gitIgnore () =
    """node_modules/
elm-stuff/

# Editors
.idea/
ElmjutsuDumMyM0DuL3.elm"""


successMessage : Colorize -> String
successMessage c =
    """
All done! """ ++ c Green "✔" ++ """

I created a """ ++ c Yellow "maintenance/MAINTENANCE.md" ++ """ file which you should read in order to learn what the next steps are, and generally how to manage the project.

I hope you'll enjoy working with """ ++ c GreenBright "elm-review" ++ """! ❤️
"""

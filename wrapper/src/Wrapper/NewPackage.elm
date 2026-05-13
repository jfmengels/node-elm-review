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
import Elm.Review.Testable.Cli as Cli
import Elm.Review.Testable.Cmd as TCmd
import Elm.Review.Testable.Fs as Fs
import Elm.Review.Testable.FsData as FsData
import Elm.Review.Testable.Internal exposing (TCmd)
import Elm.Review.Testable.ProcessData as ProcessData
import Elm.Review.Testable.TTask as TTask exposing (TTask)
import Elm.Version as Version
import ElmReview.Color as Color exposing (Color(..), Colorize)
import ElmReview.Path as Path
import ElmReview.Problem as Problem exposing (Problem)
import ElmReview.ReportMode as ReportMode
import ElmRun.ElmBinary as ElmBinary
import ElmRun.ProcessExtra as ProcessExtra
import Json.Encode as Encode
import Wrapper.MinVersion as MinVersion
import Wrapper.NewRule as NewRule
import Wrapper.Options exposing (NewPackageOptions)
import Wrapper.Options.RuleType as RuleType exposing (RuleType)
import Wrapper.ReviewConfigTemplate as ReviewConfigTemplate


type Model
    = Model ModelData


type alias ModelData =
    { stdinSupported : Bool
    , options : NewPackageOptions
    }


type Msg
    = GotUserInput Input
    | Done (Result Problem ())


type alias Input =
    { authorName : String
    , packageName : String
    , fullPackageName : Elm.Package.Name
    , ruleName : Module.Name
    , ruleType : RuleType
    , license : License
    }


type alias Warning =
    Colorize -> String


init : Bool -> NewPackageOptions -> ( Model, TCmd Msg )
init stdinSupported options =
    ( Model
        { stdinSupported = stdinSupported
        , options = options
        }
    , -- TODO Remove hardcoded values
      TTask.succeed
        { authorName = "jfmengels"
        , packageName = "elm-review-yes"
        , fullPackageName =
            case Elm.Package.fromString "jfmengels/elm-review-yes" of
                Just name ->
                    name

                Nothing ->
                    Debug.todo "Package name: Nooooooo!"
        , ruleName =
            case Module.fromString "Hi" of
                Just name ->
                    name

                Nothing ->
                    Debug.todo "Rule name: Nooooooo!"
        , ruleType = RuleType.ModuleRule
        , license = License.bsd3
        }
        |> TTask.perform GotUserInput
    )


update : Msg -> Model -> TCmd Msg
update msg (Model model) =
    case msg of
        GotUserInput input ->
            createProject input model.options
                |> TTask.attempt Done

        Done result ->
            case result of
                Ok () ->
                    let
                        c : Colorize
                        c =
                            Color.toAnsi model.options.color
                    in
                    TCmd.batch
                        [ Cli.printlnStdout (successMessage c)
                        , Cli.exit 0
                        ]

                Err problem ->
                    Problem.stop
                        { color = model.options.color
                        , reportMode = ReportMode.HumanReadable
                        , debug = model.options.debug
                        , attemptFutureRecovery = False
                        }
                        problem


createProject : Input -> NewPackageOptions -> TTask Problem ()
createProject input options =
    let
        elmJson : Elm.Project.Project
        elmJson =
            createElmJson input

        ruleName : String
        ruleName =
            Module.toString input.ruleName
    in
    TTask.sequence
        [ -- Rule source file
          Fs.createFileAndItsDirectory
            (Path.join [ input.packageName, "src", String.replace "." "/" ruleName ++ ".elm" ])
            (NewRule.newSourceFile elmJson ruleName input.ruleType)
            |> TTask.mapError (\error -> Problem.unexpectedError "while creating the new rule's source file" (FsData.errorToString error))
        , -- Rule test file
          Fs.createFileAndItsDirectory
            (Path.join [ input.packageName, "tests", String.replace "." "/" ruleName ++ "Test.elm" ])
            (NewRule.newTestFile ruleName)
            |> TTask.mapError (\error -> Problem.unexpectedError "while creating the new rule's test file" (FsData.errorToString error))
        , -- elm.json
          createElmJsonFile elmJson input
        , -- package.json
          createPackageJsonFile input
        , -- elm-tooling.json
          createElmToolingJson input
        , -- README.md
          createReadme input
        , -- preview/
          ElmBinary.findElmVersion
            |> TTask.andThen (\elmVersion -> ReviewConfigTemplate.create elmVersion (Path.join2 input.packageName "preview") (Just ruleName))
            |> TTask.mapError (\error -> Problem.unexpectedError "while creating the preview folder's configuration" (FsData.errorToString error))
        , -- .gitignore
          Fs.writeTextFile (Path.join2 input.packageName ".gitignore") (gitIgnore ())
            |> TTask.mapError (\error -> Problem.unexpectedError "while creating the new package's .gitignore file" (FsData.errorToString error))
        , -- GitHub actions and issue template
          -- TODO Use write instead of copy?
          Fs.createDirectory (Path.join2 input.packageName ".github/ISSUE_TEMPLATE/")
            |> TTask.mapError (\error -> Problem.unexpectedError "while creating the .github/ISSUE_TEMPLATE folder" (FsData.errorToString error))
        , Fs.createDirectory (Path.join2 input.packageName ".github/workflows/")
            |> TTask.mapError (\error -> Problem.unexpectedError "while creating the .github/workflows folder" (FsData.errorToString error))
        , Fs.copyDirectory
            { from = Path.join2 options.binaryRoot "new-package/github"
            , to = Path.join2 input.packageName ".github/"
            }
            |> TTask.mapError
                (\error ->
                    let
                        stepDescription : String
                        stepDescription =
                            "while copying the GitHub Actions"
                    in
                    case error of
                        ProcessData.ProcessRunError processError ->
                            Problem.unexpectedError stepDescription (ProcessExtra.errorToString processError)

                        ProcessData.CommandNotFound ->
                            Problem.unexpectedError stepDescription "Command `cp` not found"

                        ProcessData.CommandFailed completed ->
                            Problem.unexpectedError stepDescription (Maybe.withDefault "No output." completed.stderr)
                )

        -- TODO
        --, createElmReviewConfiguration  input
        --, createLicense  input
        --, createMaintenanceScripts  input
        --, createPackageTests  input
        --, createCheckPreviewCompile  input
        ]


createElmJsonFile : Elm.Project.Project -> Input -> TTask Problem ()
createElmJsonFile elmJson input =
    let
        packageElmJson : String
        packageElmJson =
            elmJson
                |> Elm.Project.encode
                |> Encode.encode 4
    in
    Fs.writeTextFile (Path.join2 input.packageName "elm.json") packageElmJson
        |> TTask.mapError (\error -> Problem.unexpectedError "while creating the new package's elm.json file" (FsData.errorToString error))


createElmJson : Input -> Elm.Project.Project
createElmJson input =
    Elm.Project.Package
        { name = input.fullPackageName
        , summary = ""
        , license = input.license
        , version = Version.one
        , exposed = Elm.Project.ExposedList [ input.ruleName ]
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


createPackageJsonFile : Input -> TTask Problem ()
createPackageJsonFile input =
    let
        packageElmJson : String
        packageElmJson =
            packageJson input
                |> Encode.encode 4
    in
    Fs.writeTextFile (Path.join2 input.packageName "package.json") packageElmJson
        |> TTask.mapError (\error -> Problem.unexpectedError "while creating the new package's package.json file" (FsData.errorToString error))


packageJson : Input -> Encode.Value
packageJson input =
    Encode.object
        [ ( "name", Encode.string <| Elm.Package.toString input.fullPackageName )
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


createElmToolingJson : Input -> TTask Problem ()
createElmToolingJson input =
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
    Fs.writeTextFile (Path.join2 input.packageName "elm-tooling.json") elmToolingJson
        |> TTask.mapError (\error -> Problem.unexpectedError "while creating the new package's elm-tooling.json file" (FsData.errorToString error))


createReadme : Input -> TTask Problem ()
createReadme input =
    Fs.writeTextFile (Path.join2 input.packageName "README.md") (readme input)
        |> TTask.mapError (\error -> Problem.unexpectedError "while creating the new package's README file" (FsData.errorToString error))


readme : Input -> String
readme input =
    let
        fullName : String
        fullName =
            Elm.Package.toString input.fullPackageName

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

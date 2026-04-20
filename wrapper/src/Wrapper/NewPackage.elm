module Wrapper.NewPackage exposing
    ( Model, init
    , Msg, update
    )

{-|

@docs Model, init
@docs Msg, update

-}

import Capabilities exposing (Console, Stdin)
import Cli
import Elm.Constraint
import Elm.License as License exposing (License)
import Elm.Module as Module
import Elm.Package
import Elm.Project
import Elm.Review.CliVersion as CliVersion
import Elm.Version as Version
import ElmReview.Color as Color exposing (Color(..), Colorize)
import ElmReview.Path as Path exposing (Path)
import ElmReview.Problem as Problem exposing (Problem)
import ElmReview.ReportMode as ReportMode
import ElmRun.ElmBinary as ElmBinary
import ElmRun.FsExtra as FsExtra
import ElmRun.OsExtra as OsExtra
import Fs exposing (FileSystem, FsError)
import Json.Encode as Encode
import Os exposing (ProcessCapability)
import Platform exposing (Task)
import Task
import Wrapper.MinVersion as MinVersion
import Wrapper.NewRule as NewRule
import Wrapper.Options exposing (NewPackageOptions)
import Wrapper.Options.RuleType as RuleType exposing (RuleType)
import Wrapper.ReviewConfigTemplate as ReviewConfigTemplate


type Model
    = Model ModelData


type alias ModelData =
    { stdout : Console
    , stderr : Console
    , stdin : Maybe Stdin
    , fs : FileSystem
    , os : ProcessCapability
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


init : { env | stdout : Console, stderr : Console, stdin : Maybe Stdin } -> { capabilities | fs : FileSystem, os : ProcessCapability } -> NewPackageOptions -> ( Model, Cmd Msg )
init { stdout, stderr, stdin } { fs, os } options =
    ( Model
        { stdout = stdout
        , stderr = stderr
        , stdin = stdin
        , fs = fs
        , os = os
        , options = options
        }
    , -- TODO Remove hardcoded values
      Task.succeed
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
        |> Task.perform GotUserInput
    )


update : Msg -> Model -> Cmd Msg
update msg (Model model) =
    case msg of
        GotUserInput input ->
            createProject input model
                |> Task.attempt Done

        Done result ->
            case result of
                Ok () ->
                    let
                        c : Colorize
                        c =
                            Color.toAnsi model.options.color
                    in
                    Cmd.batch
                        [ Cli.println model.stdout (successMessage c)
                        , Cli.exit 0
                        ]

                Err problem ->
                    Problem.exit model.stderr
                        { color = model.options.color
                        , reportMode = ReportMode.HumanReadable
                        , debug = model.options.debug
                        }
                        problem


createProject : Input -> ModelData -> Task Problem ()
createProject input { fs, os, options } =
    let
        elmJson : Elm.Project.Project
        elmJson =
            createElmJson input

        ruleName : String
        ruleName =
            Module.toString input.ruleName
    in
    Task.sequence
        [ -- Rule source file
          FsExtra.createFileAndItsDirectory
            fs
            (Path.join [ input.packageName, "src", String.replace "." "/" ruleName ++ ".elm" ])
            (NewRule.newSourceFile elmJson ruleName input.ruleType)
            |> Task.mapError (\error -> Problem.unexpectedError "while creating the new rule's source file" (FsExtra.errorToString error))
        , -- Rule test file
          FsExtra.createFileAndItsDirectory
            fs
            (Path.join [ input.packageName, "tests", String.replace "." "/" ruleName ++ "Test.elm" ])
            (NewRule.newTestFile ruleName)
            |> Task.mapError (\error -> Problem.unexpectedError "while creating the new rule's test file" (FsExtra.errorToString error))
        , -- elm.json
          createElmJsonFile fs elmJson input
        , -- package.json
          createPackageJsonFile fs input
        , -- elm-tooling.json
          createElmToolingJson fs input
        , -- README.md
          createReadme fs input
        , -- preview/
          ElmBinary.findElmVersion os
            |> Task.andThen (\elmVersion -> ReviewConfigTemplate.create fs elmVersion (Path.join2 input.packageName "preview") (Just ruleName))
            |> Task.mapError (\error -> Problem.unexpectedError "while creating the preview folder's configuration" (FsExtra.errorToString error))
        , -- .gitignore
          Fs.writeTextFile fs (Path.join2 input.packageName ".gitignore") (gitIgnore ())
            |> Task.mapError (\error -> Problem.unexpectedError "while creating the new package's .gitignore file" (FsExtra.errorToString error))
        , -- GitHub actions and issue template
          -- TODO Use write instead of copy?
          Fs.createDirectory fs (Path.join2 input.packageName ".github/ISSUE_TEMPLATE/")
            |> Task.mapError (\error -> Problem.unexpectedError "while creating the .github/ISSUE_TEMPLATE folder" (FsExtra.errorToString error))
        , Fs.createDirectory fs (Path.join2 input.packageName ".github/workflows/")
            |> Task.mapError (\error -> Problem.unexpectedError "while creating the .github/workflows folder" (FsExtra.errorToString error))
        , FsExtra.copyDirectory os
            { -- TODO Use path relative to this binary
              from = "/Users/m1/dev/node-elm-review/new-package/github"
            , to = Path.join2 input.packageName ".github/"
            }
            |> Task.mapError (\error -> Problem.unexpectedError "while copying the GitHub Actions" (OsExtra.errorToString error))

        -- TODO
        --, createElmReviewConfiguration fs input
        --, createLicense fs input
        --, createMaintenanceScripts fs input
        --, createPackageTests fs input
        --, createCheckPreviewCompile fs input
        ]
        |> Task.map (\_ -> ())


createElmJsonFile : FileSystem -> Elm.Project.Project -> Input -> Task Problem ()
createElmJsonFile fs elmJson input =
    let
        packageElmJson : String
        packageElmJson =
            elmJson
                |> Elm.Project.encode
                |> Encode.encode 4
    in
    Fs.writeTextFile fs (Path.join2 input.packageName "elm.json") packageElmJson
        |> Task.mapError (\error -> Problem.unexpectedError "while creating the new package's elm.json file" (FsExtra.errorToString error))


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


createPackageJsonFile : FileSystem -> Input -> Task Problem ()
createPackageJsonFile fs input =
    let
        packageElmJson : String
        packageElmJson =
            packageJson input
                |> Encode.encode 4
    in
    Fs.writeTextFile fs (Path.join2 input.packageName "package.json") packageElmJson
        |> Task.mapError (\error -> Problem.unexpectedError "while creating the new package's package.json file" (FsExtra.errorToString error))


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
    , ( "fs-extra", "^9.0.0" )
    , ( "npm-run-all", "^4.1.5" )
    , ( "tinyglobby", "^0.2.16" )
    ]
        |> List.map (\( name, script ) -> ( name, Encode.string script ))


createElmToolingJson : FileSystem -> Input -> Task Problem ()
createElmToolingJson fs input =
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
    Fs.writeTextFile fs (Path.join2 input.packageName "elm-tooling.json") elmToolingJson
        |> Task.mapError (\error -> Problem.unexpectedError "while creating the new package's elm-tooling.json file" (FsExtra.errorToString error))


createReadme : FileSystem -> Input -> Task Problem ()
createReadme fs input =
    Fs.writeTextFile fs (Path.join2 input.packageName "README.md") (readme input)
        |> Task.mapError (\error -> Problem.unexpectedError "while creating the new package's README file" (FsExtra.errorToString error))


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

module Wrapper.Build exposing (build, BuildData)

{-|

@docs build, BuildData

-}

import Elm.Package
import Elm.Project
import Elm.Review.Testable.Fs as Fs
import Elm.Review.Testable.FsData as FsData exposing (FsError)
import Elm.Review.Testable.Process as Process
import Elm.Review.Testable.ProcessData as ProcessData exposing (ProcessError)
import Elm.Review.Testable.TTask as TTask exposing (TTask)
import Elm.Version exposing (Version)
import ElmReview.Color as Color exposing (Color(..))
import ElmReview.Path as Path exposing (Path)
import ElmReview.Problem as Problem exposing (Problem, ProblemSimple)
import ElmRun.FsExtra as FsExtra
import ElmRun.ProcessExtra as ProcessExtra
import Json.Decode as Decode
import Json.Encode as Encode
import Set exposing (Set)
import Wrapper.FetchRemoteTemplate as FetchRemoteTemplate
import Wrapper.FolderHash as FolderHash
import Wrapper.Hash exposing (Hash)
import Wrapper.MinVersion as MinVersion
import Wrapper.OptimizeJs as OptimizeJs
import Wrapper.Options as Options exposing (ReviewOptions, ReviewProject)
import Wrapper.OutputTarget as OutputTarget exposing (OutputTarget)
import Wrapper.ProcessEnv as ProcessEnv exposing (ProcessEnv)
import Wrapper.ProjectPaths as ProjectPaths exposing (ProjectPaths)


type alias BuildData =
    { reviewAppPath : Path
    , elmJsonPath : Path
    , packagesLocation : Path
    , reviewElmJson : Elm.Project.ApplicationInfo
    , elmReviewVersion : Version
    , appHash : Hash
    }


type alias BuildOptions options =
    { options
        | projectPaths : ProjectPaths
        , debug : Bool
        , forceBuild : Bool
        , offline : Bool
        , color : Color.Support
        , reviewProject : ReviewProject
        , localElmReview : Maybe Path
        , elmCompilerPath : Maybe Path
        , processEnv : ProcessEnv
        , binaryRoot : Path
        , elmHomePath : Path
        , outputTarget : OutputTarget
    }


build : BuildOptions options -> TTask Problem BuildData
build options =
    case options.reviewProject of
        Options.Local reviewFolder ->
            buildProject options reviewFolder

        Options.Remote remoteTemplate ->
            FetchRemoteTemplate.checkoutGitRepository options.offline remoteTemplate options.debug
                |> TTask.andThen (\reviewFolder -> buildProject options reviewFolder)


buildProject : BuildOptions options -> Path -> TTask Problem BuildData
buildProject options reviewFolder =
    let
        elmJsonPath : String
        elmJsonPath =
            Path.join2 reviewFolder "elm.json"
    in
    readReviewElmJson options.reviewProject elmJsonPath
        |> TTask.andThen (\elmJson -> validateElmReviewVersion options elmJsonPath elmJson.application |> TTask.fromResult)
        |> TTask.andThen
            (\{ application, elmReviewVersion } ->
                FolderHash.hashApplication reviewFolder options.localElmReview application
                    |> TTask.mapError (fsErrorToProblem "while building and hashing source-directories")
                    |> TTask.andThen
                        (\appHash ->
                            let
                                reviewAppPath : Path
                                reviewAppPath =
                                    ProjectPaths.reviewApp options.projectPaths options.outputTarget appHash

                                packagesLocation : Path
                                packagesLocation =
                                    Path.join [ options.elmHomePath, Elm.Version.toString application.elm, "packages" ]

                                buildData : BuildData
                                buildData =
                                    { reviewAppPath = reviewAppPath
                                    , elmJsonPath = elmJsonPath
                                    , packagesLocation = packagesLocation
                                    , reviewElmJson = application
                                    , elmReviewVersion = elmReviewVersion
                                    , appHash = appHash
                                    }
                            in
                            reuseExistingReviewApp options.forceBuild reviewAppPath
                                |> TTask.andThen
                                    (\exists ->
                                        if exists then
                                            TTask.succeed ()

                                        else
                                            buildCreatedProject
                                                reviewFolder
                                                options
                                                buildData
                                    )
                                |> TTask.map (\() -> buildData)
                        )
            )


validateElmReviewVersion : BuildOptions options -> Path -> Elm.Project.ApplicationInfo -> Result Problem { application : Elm.Project.ApplicationInfo, elmReviewVersion : Version }
validateElmReviewVersion options elmJsonPath elmJson =
    -- TODO For templates, try to upgrade dependencies if they don't match
    case MinVersion.validateDependencyVersion options.reviewProject options.localElmReview elmJson of
        Err problem ->
            problem
                |> Problem.from Problem.Recoverable
                |> Problem.withPath elmJsonPath
                |> Err

        Ok version ->
            Ok
                { application = elmJson
                , elmReviewVersion = version
                }


reuseExistingReviewApp : Bool -> String -> TTask x Bool
reuseExistingReviewApp forceBuild reviewAppPath =
    if forceBuild then
        TTask.succeed False

    else
        Fs.stat reviewAppPath
            |> TTask.map (\_ -> True)
            |> TTask.onError (\_ -> TTask.succeed False)


buildCreatedProject : Path -> BuildOptions options -> BuildData -> TTask Problem ()
buildCreatedProject reviewFolder options buildData =
    let
        buildFolder : Path
        buildFolder =
            ProjectPaths.buildFolder options.projectPaths "review-project"

        localElmReviewTasks : { setUp : TTask Problem (), cleanUp : TTask Problem () }
        localElmReviewTasks =
            createSymLinkForLocalElmReview
                { buildFolder = buildFolder
                , localElmReview = options.localElmReview
                , packagesLocation = buildData.packagesLocation
                , elmReviewVersion = buildData.elmReviewVersion
                }
    in
    TTask.sequence
        [ Fs.createDirectory (Path.join2 buildFolder "src")
            |> TTask.mapError (fsErrorToProblem "while building and creating temporary source directory")
        , Fs.createDirectory (Path.dirname buildData.reviewAppPath)
            |> TTask.mapError (fsErrorToProblem "while building and creating temporary directory")
        , Fs.copyDirectory
            { from = Path.join2 options.binaryRoot "template/src"
            , to = buildFolder
            }
            |> TTask.mapError
                (\error ->
                    let
                        stepDescription : String
                        stepDescription =
                            "while building and copying template files"
                    in
                    case error of
                        ProcessData.ProcessRunError processError ->
                            processErrorToProblem stepDescription processError

                        ProcessData.CommandNotFound ->
                            Problem.unexpectedError stepDescription "Command `cp` not found"

                        ProcessData.CommandFailed completed ->
                            Problem.unexpectedError stepDescription (Maybe.withDefault "No output." completed.stderr)
                )
        , createTemplateElmJson options.outputTarget reviewFolder options.binaryRoot buildFolder buildData.reviewElmJson
        , localElmReviewTasks.setUp
        , compileProject options reviewFolder buildFolder buildData.reviewAppPath
            |> TTask.alwaysRun localElmReviewTasks.cleanUp
        ]


createSymLinkForLocalElmReview :
    { buildFolder : Path
    , localElmReview : Maybe Path
    , packagesLocation : Path
    , elmReviewVersion : Version
    }
    -> { setUp : TTask Problem (), cleanUp : TTask x () }
createSymLinkForLocalElmReview { buildFolder, localElmReview, packagesLocation, elmReviewVersion } =
    case localElmReview of
        Nothing ->
            { setUp = TTask.succeed (), cleanUp = TTask.succeed () }

        Just localElmReview_ ->
            let
                packagePath : Path
                packagePath =
                    Path.join [ packagesLocation, "jfmengels/elm-review", Elm.Version.toString elmReviewVersion, "elm.json" ]

                elmStuffForBuild : Path
                elmStuffForBuild =
                    Path.join2 buildFolder "elm-stuff"
            in
            { setUp =
                TTask.sequence
                    [ -- TODO Move code rather than delete it?
                      -- Fs.createTempDirectory  "elm-review"
                      Fs.removeDirectory packagePath
                        |> TTask.onError (\_ -> TTask.succeed ())
                    , Fs.removeDirectory elmStuffForBuild
                        |> TTask.onError (\_ -> TTask.succeed ())
                    , Fs.deleteFile (Path.join2 localElmReview_ "artifacts.dat")
                        |> TTask.onError (\_ -> TTask.succeed ())
                    , -- TODO Create a symlink instead
                      Fs.copyDirectory { from = localElmReview_, to = packagePath }
                        |> TTask.mapError
                            (\error ->
                                let
                                    stepDescription : String
                                    stepDescription =
                                        "while copying the LOCAL_ELM_REVIEW package from " ++ localElmReview_ ++ " to " ++ packagePath
                                in
                                case error of
                                    ProcessData.ProcessRunError processError ->
                                        processErrorToProblem stepDescription processError

                                    ProcessData.CommandNotFound ->
                                        Problem.unexpectedError stepDescription "Command `cp` not found"

                                    ProcessData.CommandFailed completed ->
                                        Problem.unexpectedError stepDescription (Maybe.withDefault "No output." completed.stderr)
                            )
                    ]
            , cleanUp =
                TTask.sequence
                    [ Fs.removeDirectory packagePath
                        |> TTask.onError (\_ -> TTask.succeed ())
                    , Fs.removeDirectory elmStuffForBuild
                        |> TTask.onError (\_ -> TTask.succeed ())
                    ]
            }


createTemplateElmJson : OutputTarget -> Path -> Path -> Path -> Elm.Project.ApplicationInfo -> TTask Problem ()
createTemplateElmJson outputTarget reviewFolder binaryRoot buildFolder reviewElmJson =
    let
        dependencies : List ( Elm.Package.Name, Elm.Version.Version )
        dependencies =
            reviewElmJson.depsDirect
                ++ reviewElmJson.depsIndirect
                |> addReviewAppDependencies outputTarget

        elmJson : Elm.Project.ApplicationInfo
        elmJson =
            { reviewElmJson
                | dirs =
                    "src"
                        :: Path.join2 binaryRoot "elm-run/src"
                        :: Path.join2 binaryRoot "ast-codec/src"
                        :: List.map (\dir -> Path.join2 reviewFolder dir) reviewElmJson.dirs
                , depsDirect = dependencies
                , depsIndirect = []
                , testDepsDirect = []
                , testDepsIndirect = []
            }
    in
    Fs.writeTextFile
        (Path.join2 buildFolder "elm.json")
        (Elm.Project.encode (Elm.Project.Application elmJson) |> Encode.encode 2)
        |> TTask.map (always ())
        |> TTask.mapError (fsErrorToProblem "while building and writing the review application's elm.json")


fsErrorToProblem : String -> FsError -> Problem
fsErrorToProblem stepDescription error =
    Problem.unexpectedError stepDescription (FsData.errorToString error)


processErrorToProblem : String -> ProcessError -> Problem
processErrorToProblem stepDescription error =
    Problem.unexpectedError stepDescription (ProcessData.errorToString error)


addReviewAppDependencies : OutputTarget -> List ( Elm.Package.Name, Elm.Version.Version ) -> List ( Elm.Package.Name, Elm.Version.Version )
addReviewAppDependencies outputTarget initialDependencies =
    -- TODO Use a real solver algorithm that respects the `--offline` flag
    let
        alreadyPresent : Set String
        alreadyPresent =
            Set.fromList (List.map (\( name, _ ) -> Elm.Package.toString name) initialDependencies)
    in
    List.foldl
        (\( pkgName, pkgVersion ) deps ->
            if Set.member pkgName alreadyPresent then
                deps

            else
                case ( Elm.Package.fromString pkgName, Elm.Version.fromString pkgVersion ) of
                    ( Just name, Just version ) ->
                        ( name, version ) :: deps

                    _ ->
                        Debug.todo "Report error"
        )
        initialDependencies
        ([ ( "elm/json", "1.1.4" )
         , ( "elm/regex", "1.0.0" )
         , ( "elm/parser", "1.1.0" )
         , ( "elm/http", "2.0.0" )
         , ( "elm/file", "1.0.5" )
         , ( "stil4m/elm-syntax", "7.3.9" )
         , ( "elm/project-metadata-utils", "1.0.2" )
         , ( "robinheghan/fnv1a", "1.0.0" )
         , ( "rtfeldman/elm-hex", "1.0.0" )
         , ( "stil4m/structured-writer", "1.0.3" )
         ]
            ++ (case outputTarget of
                    OutputTarget.JavaScriptTarget ->
                        []

                    OutputTarget.ElmRunTarget ->
                        [ ( "elm-run/cli", "1.0.0" )
                        , ( "elm-run/fs", "1.0.0" )
                        , ( "elm-run/os", "1.0.0" )
                        , ( "elm-run/worker", "1.0.0" )
                        , ( "elm-run/capabilities", "1.0.0" )
                        , ( "elm-run/log", "1.0.0" )
                        , ( "elm-run/stdio", "1.0.0" )
                        ]
               )
        )


readReviewElmJson : ReviewProject -> Path -> TTask Problem { raw : String, application : Elm.Project.ApplicationInfo }
readReviewElmJson reviewProject elmJsonPath =
    fetchElmJson reviewProject elmJsonPath
        |> TTask.andThen
            (\rawElmJson ->
                parseElmJson reviewProject elmJsonPath rawElmJson
                    |> Result.map (\application -> { raw = rawElmJson, application = application })
                    |> TTask.fromResult
            )


fetchElmJson : ReviewProject -> Path -> TTask Problem String
fetchElmJson reviewProject elmJsonPath =
    Fs.readTextFile elmJsonPath
        |> TTask.mapError
            (\error ->
                case error of
                    FsData.NotFound _ ->
                        elmJsonNotFoundProblem reviewProject elmJsonPath

                    FsData.PermissionDenied ->
                        { title = "PERMISSION DENIED"
                        , message =
                            \c ->
                                "I tried reading " ++ c Yellow elmJsonPath ++ """ but couldn't because of the file's read permissions.

Try changing the permissions of the file and/or its parents directories."""
                        }
                            |> Problem.from Problem.Recoverable
                            |> Problem.withPath elmJsonPath

                    FsData.IoError "Not a directory" ->
                        notADirectoryConfigurationProblem elmJsonPath

                    FsData.IoError message ->
                        Problem.unexpectedError ("when trying to read " ++ elmJsonPath) message
                            |> Problem.withPath elmJsonPath
            )


elmJsonNotFoundProblem : ReviewProject -> Path -> Problem
elmJsonNotFoundProblem reviewProject elmJsonPath =
    case reviewProject of
        Options.Local reviewFolder ->
            { title = "INCORRECT CONFIGURATION"
            , message =
                \c ->
                    "I could not find a review configuration. I was expecting to find an " ++ c Yellow "elm.json" ++ " file and a " ++ c Cyan "ReviewConfig.elm" ++ " file in " ++ c Cyan (reviewFolder ++ "/") ++ """.

I can help set you up with an initial configuration if you run """ ++ c Magenta "elm-review init" ++ "."
            }
                |> Problem.from Problem.Recoverable
                |> Problem.withPath elmJsonPath

        Options.Remote remoteTemplate ->
            let
                templateElmJsonPath : Path
                templateElmJsonPath =
                    Path.join2 (Maybe.withDefault "." remoteTemplate.pathToFolder) "elm.json"
            in
            { title = "TEMPLATE ELM.JSON NOT FOUND"
            , message =
                \c -> "I found the " ++ c Yellow remoteTemplate.repoName ++ """ repository on GitHub,
but I could not find a """ ++ c Yellow templateElmJsonPath ++ """ file in it.

I need this file to determine the rest of the configuration."""
            }
                |> Problem.from Problem.Unrecoverable


notADirectoryConfigurationProblem : Path -> Problem
notADirectoryConfigurationProblem elmJsonPath =
    { title = "INCORRECT CONFIGURATION"
    , message =
        \c -> "I was expecting the configuration to be a path to a directory containing an " ++ c Yellow "elm.json" ++ " file and a " ++ c Cyan "ReviewConfig.elm" ++ " file, but it seems " ++ c Red "you pointed at a file" ++ """.

Instead of """ ++ c Red "--config some/path/to/review/elm.json" ++ """ (or similar),
please use """ ++ c GreenBright "--config some/path/to/review"
    }
        |> Problem.from Problem.Unrecoverable
        |> Problem.withPath elmJsonPath


parseElmJson : ReviewProject -> String -> String -> Result Problem Elm.Project.ApplicationInfo
parseElmJson reviewProject elmJsonPath rawElmJson =
    case Decode.decodeString Elm.Project.decoder rawElmJson of
        Err error ->
            Err (Problem.invalidElmJson elmJsonPath reviewProject error)

        Ok (Elm.Project.Package _) ->
            case reviewProject of
                Options.Local _ ->
                    { title = "REVIEW CONFIG IS NOT AN APPLICATION"
                    , message =
                        \c ->
                            "I wanted to use " ++ c Yellow elmJsonPath ++ " as the basis for the configuration, and I expected it to be an " ++ c Yellow "application" ++ """, but it wasn't.

I think it is likely that you are pointing to an incorrect configuration file. Please check the path to your configuration again."""
                    }
                        |> Problem.from Problem.Recoverable
                        |> Problem.withPath elmJsonPath
                        |> Err

                Options.Remote { repoName, reference } ->
                    let
                        referenceAsUrl : String
                        referenceAsUrl =
                            case reference of
                                Just ref ->
                                    "#" ++ ref

                                Nothing ->
                                    ""
                    in
                    { title = "INVALID TEMPLATE ELM.JSON TYPE"
                    , message =
                        \c ->
                            "I found the " ++ c Yellow "elm.json" ++ " associated with " ++ c Yellow repoName ++ """ repository on GitHub,
but it is of type """ ++ c Red "package" ++ " when I need it to be of type " ++ c Yellow "application" ++ """.

Maybe you meant to target the """ ++ c Cyan "example" ++ " or the " ++ c Cyan "preview" ++ """ folder in that repository?

    elm-review --template """ ++ repoName ++ "/example" ++ referenceAsUrl ++ """
    elm-review --template """ ++ repoName ++ "/review" ++ referenceAsUrl
                    }
                        |> Problem.from Problem.Unrecoverable
                        |> Err

        Ok (Elm.Project.Application application) ->
            Ok application


compileProject : BuildOptions options -> Path -> Path -> String -> TTask Problem ()
compileProject options reviewFolder buildFolder reviewAppPath =
    case options.outputTarget of
        OutputTarget.JavaScriptTarget ->
            compileProjectUsingElmMake options reviewFolder buildFolder reviewAppPath

        OutputTarget.ElmRunTarget ->
            compileProjectUsingElmRun options.processEnv reviewFolder buildFolder reviewAppPath


compileProjectUsingElmMake : BuildOptions options -> Path -> Path -> String -> TTask Problem ()
compileProjectUsingElmMake options reviewFolder buildFolder reviewAppPath =
    let
        elmBinary : Path
        elmBinary =
            -- TODO Apply `backwardsCompatiblePath` from `elm-binary.js`?
            Maybe.withDefault "elm" options.elmCompilerPath
    in
    Process.run
        elmBinary
        { args =
            [ "make"
            , "--output"
            , reviewAppPath
            , if options.debug then
                "--debug"

              else
                "--optimize"
            , "src/Elm/Review/NodeMain.elm"
            ]

        -- TODO Force color. Setting an env currently unsets all other variables like PATH and makes the process crash.
        , env = Just (ProcessEnv.asProcessEnv options.processEnv)
        , cwd = Just buildFolder
        , stdin = ProcessData.NullStdin
        , stdout = ProcessData.NullStdout
        , stderr = ProcessData.CaptureStderr { maxBytes = 8 * 1024 * 1024, onOverflow = ProcessData.TruncateOutput }
        }
        |> TTask.mapError
            (\error ->
                case error of
                    ProcessData.ProcessRunError processError ->
                        processErrorToProblem "while building the review application binary" processError

                    ProcessData.CommandNotFound ->
                        elmNotFoundError { usedPath = elmBinary, elmCompilerPath = options.elmCompilerPath }

                    ProcessData.CommandFailed completed ->
                        compilationError reviewFolder completed.stderr
                            |> Problem.from Problem.Recoverable
            )
        |> TTask.andThen (\_ -> OptimizeJs.optimize options.debug reviewAppPath)


elmNotFoundError : { usedPath : Path, elmCompilerPath : Maybe Path } -> Problem
elmNotFoundError { usedPath, elmCompilerPath } =
    { title = "ELM NOT FOUND"
    , message =
        \c ->
            case elmCompilerPath of
                Nothing ->
                    "I could not find the executable for the " ++ c MagentaBright "elm" ++ """ compiler.

A few options:
- Install it globally
- Specify the path using """ ++ c Cyan "--compiler <path-to-elm>"

                Just elmCompilerPath_ ->
                    "I could not find the executable for the " ++ c MagentaBright "elm" ++ " compiler at the location you specified:\n  " ++ elmCompilerPath_
    }
        |> Problem.from Problem.Unrecoverable
        |> Problem.withPath usedPath


compileProjectUsingElmRun : ProcessEnv -> Path -> Path -> String -> TTask Problem ()
compileProjectUsingElmRun processEnv reviewFolder buildFolder reviewAppPath =
    Process.run
        -- TODO Get run from somewhere
        "run"
        { args =
            [ "make"
            , "--trust-always"
            , "-o"
            , reviewAppPath
            , Path.join2 buildFolder "src/Elm/Review/ElmRunMain.elm"
            ]

        -- TODO Force color. Setting an env currently unsets all other variables like PATH and makes the process crash.
        , env = Just (ProcessEnv.asProcessEnv processEnv)
        , cwd = Nothing
        , stdin = ProcessData.NullStdin
        , stdout = ProcessData.NullStdout
        , stderr = ProcessData.CaptureStderr { maxBytes = 8 * 1024 * 1024, onOverflow = ProcessData.TruncateOutput }
        }
        |> TTask.mapError
            (\error ->
                case error of
                    ProcessData.ProcessRunError processError ->
                        processErrorToProblem "while building the review application binary" processError

                    ProcessData.CommandNotFound ->
                        { title = "COMMAND NOT FOUND"

                        -- TODO Make "run not found" helper more helpful, e.g. by adding installations details.
                        , message = \c -> "I could not find the " ++ c Yellow "run" ++ " executable. Is it installed on your system?"
                        }
                            |> Problem.from Problem.Recoverable

                    ProcessData.CommandFailed completed ->
                        compilationError reviewFolder completed.stderr
                            |> Problem.from Problem.Recoverable
            )
        |> TTask.map (\_ -> ())


compilationError : Path -> Maybe String -> ProblemSimple
compilationError reviewFolder stderr =
    let
        output : String
        output =
            case stderr of
                Nothing ->
                    "No compiler output."

                Just "" ->
                    "No compiler output."

                Just message ->
                    message
    in
    if String.contains "DEBUG REMNANTS" output then
        { title = "DEBUG IN CONFIGURATION"
        , message = \c -> "You are using the " ++ c Yellow "Debug" ++ " module in your configuration or rules, but I am compiling in optimized mode. Either remove those uses or run elm-review with " ++ c Yellow "--debug" ++ "."
        }

    else if String.contains "MODULE NOT FOUND" output then
        { title = "MODULE NOT FOUND"
        , message = \c -> "A module is missing in your configuration. Maybe you forgot to add some dependencies that contain the rules you wished to enable? If so, run " ++ c Magenta "elm install" ++ " with the package name from inside " ++ c Yellow reviewFolder ++ """.

Here is the full error message:

""" ++ output
        }

    else
        { title = "CONFIGURATION COMPILATION ERROR"
        , message = \c -> "Errors occurred while compiling your configuration for " ++ c GreenBright "elm-review" ++ ". I need your configuration to compile in order to know how to analyze your files. Hopefully the compiler error below will help you figure out how to fix it.\n\n" ++ output
        }

module Wrapper.Build exposing (build, BuildData)

{-|

@docs build, BuildData

-}

import Elm.Package
import Elm.Project
import Elm.Version
import ElmReview.Color exposing (Color(..), Colorize)
import ElmReview.Path as Path exposing (Path)
import ElmReview.Problem as Problem exposing (Problem, ProblemSimple)
import ElmRun.FsExtra as FsExtra
import ElmRun.OsExtra as OsExtra
import ElmRun.TaskExtra as TaskExtra
import Fs exposing (FileSystem, FsError)
import Json.Decode as Decode
import Json.Encode as Encode
import Os exposing (ProcessCapability)
import Os.Process as Process exposing (ProcessError)
import Set exposing (Set)
import Task exposing (Task)
import Wrapper.FetchRemoteTemplate as FetchRemoteTemplate
import Wrapper.FolderHash as FolderHash
import Wrapper.Hash exposing (Hash)
import Wrapper.MinVersion as MinVersion
import Wrapper.Options as Options exposing (ReviewOptions, ReviewProject)
import Wrapper.ProjectPaths as ProjectPaths
import Wrapper.RemoteTemplate exposing (RemoteTemplate)


type alias BuildData =
    { reviewAppPath : Path
    , elmJsonPath : Path
    , reviewElmJson : Elm.Project.ApplicationInfo
    , appHash : Hash
    }


build : FileSystem -> ProcessCapability -> ReviewOptions -> Task Problem BuildData
build fs os options =
    case options.reviewProject of
        Options.Local reviewFolder ->
            buildLocalProject fs os options reviewFolder

        Options.Remote remoteTemplate ->
            FetchRemoteTemplate.checkoutGitRepository fs os remoteTemplate options.debug
                |> Task.andThen (\reviewFolder -> buildLocalProject fs os options reviewFolder)


buildLocalProject : FileSystem -> ProcessCapability -> ReviewOptions -> Path -> Task Problem BuildData
buildLocalProject fs os options reviewFolder =
    let
        elmJsonPath : String
        elmJsonPath =
            Path.join2 reviewFolder "elm.json"
    in
    readReviewElmJson fs options.reviewProject elmJsonPath
        |> Task.andThen (\elmJson -> validateElmReviewVersion options.reviewProject elmJsonPath elmJson |> TaskExtra.resultToTask)
        |> Task.andThen
            (\{ raw, application } ->
                FolderHash.hashApplication fs reviewFolder application
                    |> Task.mapError (fsErrorToProblem "while building and hashing source-directories")
                    |> Task.andThen
                        (\appHash ->
                            let
                                reviewAppPath : Path
                                reviewAppPath =
                                    ProjectPaths.reviewApp options.projectPaths appHash

                                buildData : BuildData
                                buildData =
                                    { reviewAppPath = reviewAppPath
                                    , elmJsonPath = elmJsonPath
                                    , reviewElmJson = application
                                    , appHash = appHash
                                    }
                            in
                            reuseExistingReviewApp fs options.forceBuild reviewAppPath
                                |> Task.andThen
                                    (\exists ->
                                        if exists then
                                            Task.succeed ()

                                        else
                                            buildLocalProjectBuild
                                                fs
                                                os
                                                reviewFolder
                                                (ProjectPaths.buildFolder options.projectPaths "review-project")
                                                buildData
                                    )
                                |> Task.map (\() -> buildData)
                        )
            )


validateElmReviewVersion : ReviewProject -> Path -> { raw : String, application : Elm.Project.ApplicationInfo } -> Result Problem { raw : String, application : Elm.Project.ApplicationInfo }
validateElmReviewVersion reviewProject elmJsonPath elmJson =
    -- TODO For templates, try to upgrade dependencies if they don't match
    case MinVersion.validateDependencyVersion reviewProject elmJson.application of
        Just problem ->
            problem
                |> Problem.from
                |> Problem.withPath elmJsonPath
                |> Err

        Nothing ->
            Ok elmJson


reuseExistingReviewApp : FileSystem -> Bool -> String -> Task x Bool
reuseExistingReviewApp fs forceBuild reviewAppPath =
    if forceBuild then
        Task.succeed False

    else
        Fs.stat fs reviewAppPath
            |> Task.map (\_ -> True)
            |> Task.onError (\_ -> Task.succeed False)


buildLocalProjectBuild : FileSystem -> ProcessCapability -> Path -> Path -> BuildData -> Task Problem ()
buildLocalProjectBuild fs os reviewFolder buildFolder buildData =
    TaskExtra.sequence
        [ Fs.createDirectory fs (Path.join2 buildFolder "src")
            |> Task.mapError (fsErrorToProblem "while building and creating temporary source directory")
        , Fs.createDirectory fs (Path.dirname buildData.reviewAppPath)
            |> Task.mapError (fsErrorToProblem "while building and creating temporary directory")
        , FsExtra.copyDirectory os
            { -- TODO Use path relative to this binary
              from = "/Users/m1/dev/node-elm-review/template/src"
            , to = buildFolder
            }
            |> Task.mapError (processingErrorToProblem "while building and copying template files")
        , createTemplateElmJson fs reviewFolder buildFolder buildData.reviewElmJson
        , compileProjectUsingElmRun os reviewFolder buildFolder buildData.reviewAppPath
        ]


createTemplateElmJson : FileSystem -> Path -> Path -> Elm.Project.ApplicationInfo -> Task Problem ()
createTemplateElmJson fs reviewFolder buildFolder reviewElmJson =
    let
        astCodecSrc : Path
        astCodecSrc =
            -- TODO Use path relative to this binary
            "/Users/m1/dev/node-elm-review/ast-codec/src"

        elmRunSrc : Path
        elmRunSrc =
            -- TODO Use path relative to this binary
            "/Users/m1/dev/node-elm-review/elm-run/src"

        dependencies : List ( Elm.Package.Name, Elm.Version.Version )
        dependencies =
            reviewElmJson.depsDirect
                ++ reviewElmJson.depsIndirect
                |> addReviewAppDependencies

        elmJson : Elm.Project.ApplicationInfo
        elmJson =
            { reviewElmJson
                | dirs =
                    "src"
                        :: Path.join2 reviewFolder elmRunSrc
                        :: Path.join2 reviewFolder astCodecSrc
                        :: List.map (\dir -> Path.join2 reviewFolder dir) reviewElmJson.dirs
                , depsDirect = dependencies
                , depsIndirect = []
                , testDepsDirect = []
                , testDepsIndirect = []
            }
    in
    Fs.writeTextFile
        fs
        (Path.join2 buildFolder "elm.json")
        (Elm.Project.encode (Elm.Project.Application elmJson) |> Encode.encode 2)
        |> Task.map (always ())
        |> Task.mapError (fsErrorToProblem "while building and writing the review application's elm.json")


fsErrorToProblem : String -> FsError -> Problem
fsErrorToProblem stepDescription error =
    Problem.unexpectedError stepDescription (FsExtra.errorToString error)


processingErrorToProblem : String -> ProcessError -> Problem
processingErrorToProblem stepDescription error =
    Problem.unexpectedError stepDescription (OsExtra.errorToString error)


addReviewAppDependencies : List ( Elm.Package.Name, Elm.Version.Version ) -> List ( Elm.Package.Name, Elm.Version.Version )
addReviewAppDependencies initialDependencies =
    -- TODO Use a real solver algorithm
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
        [ ( "elm/json", "1.1.4" )
        , ( "elm/regex", "1.0.0" )
        , ( "elm/parser", "1.1.0" )
        , ( "stil4m/elm-syntax", "7.3.9" )
        , ( "elm/project-metadata-utils", "1.0.2" )
        , ( "elm-run/cli", "1.0.0" )
        , ( "elm-run/fs", "1.0.0" )
        , ( "elm-run/os", "1.0.0" )
        , ( "elm-run/worker", "1.0.0" )
        , ( "elm-run/capabilities", "1.0.0" )
        , ( "elm-run/log", "1.0.0" )
        , ( "elm-run/stdio", "1.0.0" )
        , ( "robinheghan/fnv1a", "1.0.0" )
        , ( "rtfeldman/elm-hex", "1.0.0" )
        , ( "stil4m/structured-writer", "1.0.3" )
        ]


readReviewElmJson : FileSystem -> ReviewProject -> Path -> Task Problem { raw : String, application : Elm.Project.ApplicationInfo }
readReviewElmJson fs reviewProject elmJsonPath =
    fetchElmJson fs reviewProject elmJsonPath
        |> Task.andThen
            (\rawElmJson ->
                parseElmJson reviewProject elmJsonPath rawElmJson
                    |> Result.map (\application -> { raw = rawElmJson, application = application })
                    |> TaskExtra.resultToTask
            )


fetchElmJson : FileSystem -> ReviewProject -> Path -> Task Problem String
fetchElmJson fs reviewProject elmJsonPath =
    Fs.readTextFile fs elmJsonPath
        |> Task.mapError
            (\error ->
                case error of
                    Fs.NotFound _ ->
                        elmJsonNotFoundProblem reviewProject elmJsonPath

                    Fs.PermissionDenied ->
                        { title = "PERMISSION DENIED"
                        , message =
                            \c ->
                                "I tried reading " ++ c Yellow elmJsonPath ++ """ but couldn't because of the file's read permissions.

Try changing the permissions of the file and/or its parents directories."""
                        }
                            |> Problem.from
                            |> Problem.withPath elmJsonPath

                    Fs.IoError "Not a directory" ->
                        notADirectoryConfigurationProblem elmJsonPath

                    Fs.IoError message ->
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
                |> Problem.from
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
                |> Problem.from


notADirectoryConfigurationProblem : Path -> Problem
notADirectoryConfigurationProblem elmJsonPath =
    { title = "INCORRECT CONFIGURATION"
    , message =
        \c -> "I was expecting the configuration to be a path to a directory containing an " ++ c Yellow "elm.json" ++ " file and a " ++ c Cyan "ReviewConfig.elm" ++ " file, but it seems " ++ c Red "you pointed at a file" ++ """.

Instead of """ ++ c Red "--config some/path/to/review/elm.json" ++ """ (or similar),
please use """ ++ c GreenBright "--config some/path/to/review"
    }
        |> Problem.from
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
                        |> Problem.from
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
                        |> Problem.from
                        |> Err

        Ok (Elm.Project.Application application) ->
            Ok application


compileProjectUsingElmRun : ProcessCapability -> Path -> Path -> String -> Task Problem ()
compileProjectUsingElmRun os reviewFolder buildFolder reviewAppPath =
    Process.run os
        -- TODO Get run from somewhere
        "run"
        { args =
            [ "make"
            , "--trust-always"
            , "-o"
            , reviewAppPath
            , Path.join2 buildFolder "src/Elm/Review/Main.elm"
            ]

        -- TODO Force color. Setting an env currently unsets all other variables like PATH and makes the process crash.
        , env = Nothing
        , cwd = Nothing
        , stdin = Process.NullStdin
        , stdout = Process.NullStdout
        , stderr = Process.CaptureStderr { maxBytes = 8 * 1024 * 1024, onOverflow = Process.TruncateOutput }
        }
        |> Task.mapError (processingErrorToProblem "while building the review application binary")
        |> Task.andThen
            (\{ exitCode, stderr } ->
                if exitCode == 0 then
                    Task.succeed ()

                else
                    compilationError reviewFolder (Maybe.withDefault "No compiler output." stderr)
                        |> Problem.from
                        |> Task.fail
            )


compilationError : Path -> String -> ProblemSimple
compilationError reviewFolder stderr =
    if String.contains "DEBUG REMNANTS" stderr then
        { title = "DEBUG IN CONFIGURATION"
        , message = \c -> "You are using the " ++ c Yellow "Debug" ++ " module in your configuration or rules, but I am compiling in optimized mode. Either remove those uses or run elm-review with " ++ c Yellow "--debug" ++ "."
        }

    else if String.contains "MODULE NOT FOUND" stderr then
        { title = "MODULE NOT FOUND"
        , message = \c -> "A module is missing in your configuration. Maybe you forgot to add some dependencies that contain the rules you wished to enable? If so, run " ++ c Magenta "elm install" ++ " with the package name from inside " ++ c Yellow reviewFolder ++ """.

Here is the full error message:

""" ++ stderr
        }

    else
        { title = "CONFIGURATION COMPILATION ERROR"
        , message = \c -> "Errors occurred while compiling your configuration for " ++ c GreenBright "elm-review" ++ ". I need your configuration to compile in order to know how to analyze your files. Hopefully the compiler error below will help you figure out how to fix it.\n\n" ++ stderr
        }

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
import Fs exposing (FileSystem, FsError)
import Json.Decode as Decode
import Json.Encode as Encode
import Os exposing (ProcessCapability)
import Os.Process as Process exposing (ProcessError)
import Set exposing (Set)
import Task exposing (Task)
import Wrapper.FolderHash as FolderHash
import Wrapper.Hash exposing (Hash)
import Wrapper.MinVersion as MinVersion
import Wrapper.Options as Options exposing (ReviewOptions, ReviewProject)
import Wrapper.ProjectPaths as ProjectPaths


type alias BuildData =
    { reviewAppPath : Path
    , pathToElmJson : Path
    , reviewElmJson : Elm.Project.ApplicationInfo
    , appHash : Hash
    }


build : FileSystem -> ProcessCapability -> ReviewOptions -> Task Problem BuildData
build fs os options =
    case options.reviewProject of
        Options.Local reviewFolder ->
            buildLocalProject fs os options reviewFolder

        Options.Remote remoteTemplate ->
            Problem.notImplementedYet "Building remote template"
                |> Task.fail


buildLocalProject : FileSystem -> ProcessCapability -> ReviewOptions -> String -> Task Problem BuildData
buildLocalProject fs os options reviewFolder =
    let
        pathToElmJson : String
        pathToElmJson =
            -- TODO Use path functions
            String.join "/" [ reviewFolder, "elm.json" ]
    in
    readReviewElmJson fs options.reviewProject reviewFolder pathToElmJson
        |> Task.andThen
            (\{ raw, application } ->
                FolderHash.hashSourceDirectories fs reviewFolder application.dirs
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
                                    , pathToElmJson = pathToElmJson
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
    Task.map2 (\_ _ -> ())
        (Fs.createDirectory fs (Path.join2 buildFolder "src"))
        (Fs.createDirectory fs (Path.dirname buildData.reviewAppPath))
        |> Task.mapError (fsErrorToProblem "while building and creating temporary directories")
        |> Task.andThen
            (\() ->
                FsExtra.copyDirectory os
                    { -- TODO Use path relative to this binary
                      from = "/Users/m1/dev/node-elm-review/template/src"
                    , to = buildFolder
                    }
                    |> Task.mapError (processingErrorToProblem "while building and copying template files")
            )
        |> Task.andThen (\() -> createTemplateElmJson fs reviewFolder buildFolder buildData.reviewElmJson)
        |> Task.andThen (\() -> compileProjectUsingElmRun os reviewFolder buildFolder buildData.reviewAppPath)


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


readReviewElmJson : FileSystem -> ReviewProject -> String -> String -> Task Problem { raw : String, application : Elm.Project.ApplicationInfo }
readReviewElmJson fs reviewProject reviewFolder pathToElmJson =
    fetchElmJson fs reviewFolder pathToElmJson
        |> Task.andThen
            (\rawElmJson ->
                parseElmJson reviewProject reviewFolder pathToElmJson rawElmJson
                    |> Result.mapError (Problem.from >> Problem.withPath pathToElmJson)
                    |> resultToTask
            )


fetchElmJson : FileSystem -> String -> String -> Task Problem String
fetchElmJson fs reviewFolder pathToElmJson =
    Fs.readTextFile fs pathToElmJson
        |> Task.mapError
            (\error ->
                case error of
                    Fs.NotFound _ ->
                        { title = "INCORRECT CONFIGURATION"
                        , message =
                            \c ->
                                "I could not find a review configuration. I was expecting to find an " ++ c Yellow "elm.json" ++ " file and a " ++ c Cyan "ReviewConfig.elm" ++ " file in " ++ c Cyan (reviewFolder ++ "/") ++ """.

I can help set you up with an initial configuration if you run """ ++ c Magenta "elm-review init" ++ "."
                        }
                            |> Problem.from
                            |> Problem.withPath pathToElmJson

                    Fs.PermissionDenied ->
                        { title = "PERMISSION DENIED"
                        , message =
                            \c ->
                                "I tried reading " ++ c Yellow pathToElmJson ++ """ but couldn't because of the file's read permissions.

Try changing the permissions of the file and/or its parents directories."""
                        }
                            |> Problem.from
                            |> Problem.withPath pathToElmJson

                    Fs.IoError string ->
                        Debug.todo ("Unknown error: " ++ string)
            )


parseElmJson : ReviewProject -> String -> String -> String -> Result ProblemSimple { raw : String, application : Elm.Project.ApplicationInfo }
parseElmJson reviewProject reviewFolder pathToElmJson rawElmJson =
    case Decode.decodeString Elm.Project.decoder rawElmJson of
        Err error ->
            Err
                { title = "COULD NOT READ ELM.JSON"
                , message = decodingErrorMessage pathToElmJson error
                }

        Ok (Elm.Project.Package _) ->
            Err
                { title = "REVIEW CONFIG IS NOT AN APPLICATION"
                , message =
                    \c ->
                        "I wanted to use " ++ c Yellow pathToElmJson ++ " as the basis for the configuration, and I expected it to be an " ++ c Yellow "application" ++ """, but it wasn't.

I think it is likely that you are pointing to an incorrect configuration file. Please check the path to your configuration again."""
                }

        Ok (Elm.Project.Application application) ->
            case validateElmReviewVersion reviewProject reviewFolder application of
                Just problem ->
                    Err problem

                Nothing ->
                    Ok { raw = rawElmJson, application = application }


validateElmReviewVersion : ReviewProject -> String -> Elm.Project.ApplicationInfo -> Maybe ProblemSimple
validateElmReviewVersion reviewProject reviewFolder application =
    case find (\( name, _ ) -> Elm.Package.toString name == "jfmengels/elm-review") application.depsDirect of
        Just ( _, version ) ->
            MinVersion.validate reviewProject reviewFolder version

        Nothing ->
            Just
                { title = "MISSING ELM-REVIEW DEPENDENCY"
                , message =
                    \c ->
                        "The template's configuration does not include " ++ c GreenBright "jfmengels/elm-review" ++ """ in its direct dependencies.

Maybe you chose the wrong template, or the template is malformed. If the latter is the case, please inform the template author."""
                }


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


decodingErrorMessage : String -> Decode.Error -> Colorize -> String
decodingErrorMessage pathToElmJson error c =
    "I tried reading " ++ c Yellow pathToElmJson ++ """ but encountered an error while reading it. Please check that it is valid JSON that the Elm compiler would be happy with.

Here is the error I encountered:

""" ++ Decode.errorToString error


resultToTask : Result x a -> Task x a
resultToTask result =
    case result of
        Ok value ->
            Task.succeed value

        Err err ->
            Task.fail err


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

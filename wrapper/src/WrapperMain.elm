module WrapperMain exposing (main)

import Array exposing (Array)
import Cli exposing (Env)
import Dict exposing (Dict)
import Elm.Review.CliVersion as CliVersion
import Fs exposing (FileSystem, FsError)
import Os exposing (ProcessCapability)
import Os.Process as Process exposing (ProcessError)
import Task exposing (Task)
import Wrapper.Build as Build
import Wrapper.Color exposing (Color(..))
import Wrapper.Help as Help
import Wrapper.Options exposing (ReviewOptions)
import Wrapper.Options.Parser as OptionsParser
import Wrapper.Path exposing (Path)
import Wrapper.Problem as Problem exposing (FormatOptions, Problem)
import Wrapper.ProjectPaths as ProjectPaths


main : Cli.Program ModelWrapper Msg
main =
    Cli.program
        { init = init
        , update = updateWrapper
        , subscriptions = \_ -> Sub.none
        }


type ModelWrapper
    = Done
    | Loading LoadingModel
    | Running Model


type alias LoadingModel =
    { env : Env
    , fs : FileSystem
    , os : ProcessCapability
    , formatOptions : FormatOptions {}
    , toOptions : { elmJsonPath : String } -> OptionsParser.OptionsParseResult
    }


type alias Model =
    { env : Env
    , fs : FileSystem
    , os : ProcessCapability
    , options : ReviewOptions
    }


type Msg
    = BuildCompleted (Result Problem Build.BuildData)
    | FoundNearestElmJson (Result FsError String)
    | ReviewProcessEnded (Result ProcessError Process.Completed)


init : Env -> ( ModelWrapper, Cmd Msg )
init env =
    case requireCapabilities env of
        Err msg ->
            ( Done
            , Cmd.batch
                [ -- TODO Make pretty error
                  Cli.println env.stderr (env.programName ++ ": " ++ msg)
                , Cli.exit 1
                ]
            )

        Ok capabilities ->
            handleCliArgsParseResult env capabilities (OptionsParser.parse env)


handleCliArgsParseResult : Env -> { capabilities | fs : FileSystem, os : ProcessCapability } -> OptionsParser.OptionsParseResult -> ( ModelWrapper, Cmd Msg )
handleCliArgsParseResult env { fs, os } result =
    case result of
        OptionsParser.ParseError formatOptions problem ->
            ( Done
            , exitWithProblem env formatOptions problem
            )

        OptionsParser.ShowHelp options ->
            ( Done
            , Cmd.batch
                [ Cli.println env.stdout (Help.show options)
                , Cli.exit 0
                ]
            )

        OptionsParser.ShowVersion ->
            ( Done
            , Cmd.batch
                [ Cli.println env.stdout CliVersion.version
                , Cli.exit 0
                ]
            )

        OptionsParser.NeedElmJsonPath { formatOptions, toOptions } ->
            ( Loading
                { env = env
                , fs = fs
                , os = os
                , formatOptions = formatOptions
                , toOptions = toOptions
                }
            , getCwd fs env.env
                |> Task.andThen
                    (\cwd ->
                        -- TODO Use `\` for Windows Support?
                        String.split "/" cwd
                            |> Array.fromList
                            |> findNearestElmJson fs
                    )
                |> Task.attempt FoundNearestElmJson
            )

        OptionsParser.Review options ->
            ( Running
                { env = env
                , fs = fs
                , os = os
                , options = options
                }
            , Build.build fs os options
                |> Task.attempt BuildCompleted
            )


requireCapabilities : Env -> Result String { fs : FileSystem, os : ProcessCapability }
requireCapabilities env =
    case Fs.require env of
        Err msg ->
            Err (env.programName ++ ": " ++ msg)

        Ok fs ->
            case Os.requireProcess env of
                Err msg ->
                    Err (env.programName ++ ": " ++ msg)

                Ok os ->
                    Ok { fs = fs, os = os }


updateWrapper : Msg -> ModelWrapper -> ( ModelWrapper, Cmd Msg )
updateWrapper msg wrapper =
    case wrapper of
        Done ->
            ( wrapper, Cmd.none )

        Loading loading ->
            case msg of
                FoundNearestElmJson result ->
                    foundNearestElmJson loading result

                _ ->
                    ( wrapper, Cmd.none )

        Running model ->
            update msg model
                |> Tuple.mapFirst Running


foundNearestElmJson : LoadingModel -> Result FsError Path -> ( ModelWrapper, Cmd Msg )
foundNearestElmJson loading result =
    case result of
        Ok elmJsonPath ->
            handleCliArgsParseResult
                loading.env
                loading
                (loading.toOptions { elmJsonPath = elmJsonPath })

        Err (Fs.NotFound _) ->
            ( Done
            , { title = "COULD NOT FIND ELM.JSON"
              , message =
                    \c ->
                        "I was expecting to find an " ++ c YellowBright "elm.json" ++ """ file in the current directory or one of its parents, but I did not find one.

If you wish to run elm-review from outside your project,
try re-running it with """ ++ c Cyan "--elmjson <path-to-elm.json>" ++ "."
              }
                |> Problem.from
                |> exitWithProblem loading.env loading.formatOptions
            )

        Err error ->
            ( Done
            , Problem.unexpectedError (fsErrorToString error)
                |> exitWithProblem loading.env loading.formatOptions
            )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        BuildCompleted result ->
            case result of
                Ok { reviewAppPath } ->
                    ( model
                    , runReviewProcess model reviewAppPath
                    )

                Err problem ->
                    ( model
                    , exitWithProblem model.env model.options problem
                    )

        ReviewProcessEnded result ->
            case result of
                Ok completed ->
                    ( model
                    , Cli.exit completed.exitCode
                    )

                Err err ->
                    ( model
                    , Cmd.batch
                        [ Cli.println model.env.stdout ("error: " ++ processErrorToString err)
                        , Cli.exit 1
                        ]
                    )

        FoundNearestElmJson _ ->
            ( model, Cmd.none )


findNearestElmJson : FileSystem -> Array String -> Task Fs.FsError String
findNearestElmJson fs pathSegments =
    if Array.isEmpty pathSegments then
        Task.fail (Fs.NotFound "")

    else
        let
            path : String
            path =
                Array.push "elm.json" pathSegments |> Array.toList |> String.join "/"
        in
        Fs.stat fs path
            |> Task.map (\_ -> path)
            |> Task.onError
                (\_ ->
                    findNearestElmJson fs (Array.slice 0 -1 pathSegments)
                )


getCwd : FileSystem -> Dict String String -> Task Fs.FsError String
getCwd fs env =
    -- TODO Replace this by the following when fixed.
    -- Fs.toSandboxRel fs path "."
    case Dict.get "PWD" env of
        Just path ->
            Task.succeed path

        Nothing ->
            Task.fail (Fs.NotFound ".")


runReviewProcess : Model -> String -> Cmd Msg
runReviewProcess { os, options } appBinary =
    let
        ( cmd, args ) =
            if options.debug then
                -- TODO Get host-cli from somewhere?
                ( "host-cli"
                , "-v" :: "--trust" :: appBinary :: options.reviewAppFlags
                )

            else
                ( appBinary, options.reviewAppFlags )
    in
    Process.run os
        cmd
        { args = args
        , cwd = Just (ProjectPaths.projectRoot options.projectPaths)
        , env = Nothing
        , stdin = Process.InheritStdin
        , stdout = Process.InheritStdout
        , stderr = Process.InheritStderr
        }
        |> Task.attempt ReviewProcessEnded


exitWithProblem : Env -> Problem.FormatOptions options -> Problem.Problem -> Cmd msg
exitWithProblem env formatOptions problem =
    Cmd.batch
        [ Cli.println env.stderr (Problem.format formatOptions problem)
        , Cli.exit 1
        ]


processErrorToString : ProcessError -> String
processErrorToString err =
    case err of
        Process.PermissionDenied ->
            "PermissionDenied"

        Process.CaptureLimitExceeded stream ->
            "CaptureLimitExceeded(" ++ stream ++ ")"

        Process.ProcessError message ->
            message


fsErrorToString : FsError -> String
fsErrorToString fsError =
    case fsError of
        Fs.NotFound path ->
            "File not found: " ++ path

        Fs.PermissionDenied ->
            "Permission denied"

        Fs.IoError msg ->
            "Unknown error: " ++ msg


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

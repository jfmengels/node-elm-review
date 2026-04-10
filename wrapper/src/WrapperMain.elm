module WrapperMain exposing (main)

import Array exposing (Array)
import Cli exposing (Env)
import Dict exposing (Dict)
import Elm.Review.CliVersion as CliVersion
import ElmReview.Color as Color exposing (Color(..))
import ElmReview.Path exposing (Path)
import ElmReview.Problem as Problem exposing (FormatOptions, Problem)
import ElmReview.ReportMode as ReportMode
import ElmRun.FsExtra as FsExtra
import Fs exposing (FileSystem, FsError)
import Os exposing (ProcessCapability)
import Task exposing (Task)
import Wrapper.Help as Help
import Wrapper.Init as Init
import Wrapper.Options.Parser as OptionsParser
import Wrapper.Review as Review


main : Cli.Program Model Msg
main =
    Cli.program
        { init = init
        , update = update
        , subscriptions = \_ -> Sub.none
        }


type Model
    = Done
    | Loading LoadingModel
    | Review Review.Model
    | Init Init.Model


type alias LoadingModel =
    { env : Env
    , fs : FileSystem
    , os : ProcessCapability
    , formatOptions : FormatOptions {}
    , toOptions : { elmJsonPath : Path } -> OptionsParser.OptionsParseResult
    }


type Msg
    = FoundNearestElmJson (Result FsError Path)
    | ReviewMsg Review.Msg
    | InitMsg Init.Msg


init : Env -> ( Model, Cmd Msg )
init env =
    case requireCapabilities env of
        Err err ->
            ( Done
            , { title = "MISSING CAPABILITIES"
              , message = \_ -> "elm-review was run with missing capabilities:\n\n    " ++ err
              }
                |> Problem.from
                |> Problem.exit env.stderr
                    { color = Color.noColors
                    , reportMode =
                        if List.member "--report=json" env.args || List.member "--report=ndjson" env.args then
                            ReportMode.Json

                        else
                            ReportMode.HumanReadable
                    , debug = List.member "--debug" env.args
                    }
            )

        Ok capabilities ->
            handleCliArgsParseResult env capabilities (OptionsParser.parse env)


handleCliArgsParseResult : Env -> { capabilities | fs : FileSystem, os : ProcessCapability } -> OptionsParser.OptionsParseResult -> ( Model, Cmd Msg )
handleCliArgsParseResult env { fs, os } result =
    case result of
        OptionsParser.ParseError formatOptions problem ->
            ( Done
            , Problem.exit env.stderr formatOptions problem
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
            let
                ( review, cmd ) =
                    Review.init env
                        { fs = fs
                        , os = os
                        }
                        options
            in
            ( Review review, Cmd.map ReviewMsg cmd )

        OptionsParser.Init options ->
            let
                ( initModel, cmd ) =
                    Init.init env
                        { fs = fs
                        , os = os
                        }
                        options
            in
            ( Init initModel, Cmd.map InitMsg cmd )


requireCapabilities : Env -> Result String { fs : FileSystem, os : ProcessCapability }
requireCapabilities env =
    Result.map2 (\fs os -> { fs = fs, os = os })
        (Fs.require env)
        (Os.requireProcess env)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FoundNearestElmJson result ->
            case model of
                Loading loading ->
                    foundNearestElmJson loading result

                _ ->
                    ( model, Cmd.none )

        ReviewMsg reviewMsg ->
            case model of
                Review reviewModel ->
                    ( model
                    , Review.update reviewMsg reviewModel
                        |> Cmd.map ReviewMsg
                    )

                _ ->
                    ( model, Cmd.none )

        InitMsg initMsg ->
            case model of
                Init initModel ->
                    ( model
                    , Init.update initMsg initModel
                        |> Cmd.map InitMsg
                    )

                _ ->
                    ( model, Cmd.none )


foundNearestElmJson : LoadingModel -> Result FsError Path -> ( Model, Cmd Msg )
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
                |> Problem.exit loading.env.stderr loading.formatOptions
            )

        Err error ->
            ( Done
            , Problem.unexpectedError "when trying to find your project root" (FsExtra.errorToString error)
                |> Problem.exit loading.env.stderr loading.formatOptions
            )


findNearestElmJson : FileSystem -> Array String -> Task FsError Path
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


getCwd : FileSystem -> Dict String String -> Task FsError Path
getCwd fs env =
    -- TODO Replace this by the following when fixed.
    -- Fs.toSandboxRel fs path "."
    case Dict.get "PWD" env of
        Just path ->
            Task.succeed path

        Nothing ->
            Task.fail (Fs.NotFound ".")


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

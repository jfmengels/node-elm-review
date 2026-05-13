module WrapperMain exposing (Model, Msg, main)

import Array exposing (Array)
import Dict exposing (Dict)
import Elm.Review.CliVersion as CliVersion
import Elm.Review.Testable.Cli as Cli
import Elm.Review.Testable.Cmd as TCmd
import Elm.Review.Testable.FsData exposing (FsError)
import Elm.Review.Testable.Internal exposing (TCmd)
import ElmReview.Color as Color exposing (Color(..))
import ElmReview.Path exposing (Path)
import ElmReview.Problem as Problem exposing (FormatOptions)
import ElmReview.ReportMode as ReportMode
import ElmRun.FsExtra as FsExtra
import Wrapper.Help as Help
import Wrapper.Init as Init
import Wrapper.NewPackage as NewPackage
import Wrapper.NewRule as NewRule
import Wrapper.Options.Parser as OptionsParser
import Wrapper.OutputTarget as OutputTarget
import Wrapper.PrepareOffline as PrepareOffline
import Wrapper.Review as Review


main : Cli.Program Model Msg
main =
    Cli.program
        { init = init
        , update = update
        , subscriptions = subscriptions
        }


type Model
    = Done
    | Loading LoadingModel
    | Review Review.Model
    | Init Init.Model
    | NewRule NewRule.Model
    | NewPackage NewPackage.Model
    | PrepareOffline PrepareOffline.Model


type alias LoadingModel =
    { env : Dict String String
    , formatOptions : FormatOptions {}
    , toOptions : { elmJsonPath : Path } -> OptionsParser.OptionsParseResult
    }


type Msg
    = FoundNearestElmJson (Result FsError Path)
    | ReviewMsg Review.Msg
    | InitMsg Init.Msg
    | NewRuleMsg NewRule.Msg
    | NewPackageMsg NewPackage.Msg
    | PrepareOfflineMsg PrepareOffline.Msg


init : Dict String String -> List String -> ( Model, TCmd Msg )
init env args =
    case requireCapabilities env of
        Err err ->
            ( Done
            , { title = "MISSING CAPABILITIES"
              , message = \_ -> "elm-review was run with missing capabilities:\n\n    " ++ err
              }
                |> Problem.from Problem.Unrecoverable
                |> Problem.stop
                    { color = Color.noColors
                    , reportMode =
                        if List.member "--report=json" args || List.member "--report=ndjson" args then
                            ReportMode.Json

                        else
                            ReportMode.HumanReadable
                    , debug = List.member "--debug" args
                    , attemptFutureRecovery = False
                    }
            )

        Ok capabilities ->
            let
                -- TODO Get binaryRoot path from somewhere
                binaryRoot : Path
                binaryRoot =
                    "/Users/m1/dev/node-elm-review"

                -- TODO Get elmHomePath from somewhere
                elmHomePath : String
                elmHomePath =
                    "/Users/m1/.elm"
            in
            handleCliArgsParseResult env capabilities (OptionsParser.parse env binaryRoot elmHomePath OutputTarget.JavaScriptTarget)


handleCliArgsParseResult : Dict String String -> OptionsParser.OptionsParseResult -> ( Model, TCmd Msg )
handleCliArgsParseResult env result =
    case result of
        OptionsParser.ParseError formatOptions problem ->
            ( Done
            , Problem.stop formatOptions problem
            )

        OptionsParser.ShowHelp options ->
            ( Done
            , TCmd.batch
                [ Cli.printlnStdout (Help.show options)
                , Cli.exit 0
                ]
            )

        OptionsParser.ShowVersion ->
            ( Done
            , TCmd.batch
                [ Cli.printlnStdout CliVersion.version
                , Cli.exit 0
                ]
            )

        OptionsParser.NeedElmJsonPath { formatOptions, toOptions } ->
            ( Loading
                { env = env
                , formatOptions = formatOptions
                , toOptions = toOptions
                }
            , getCwd env
                |> TTask.andThen
                    (\cwd ->
                        -- TODO Use `\` for Windows Support?
                        String.split "/" cwd
                            |> Array.fromList
                            |> findNearestElmJson fs
                    )
                |> TTask.attempt FoundNearestElmJson
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

        OptionsParser.NewRule options ->
            let
                ( newRuleModel, cmd ) =
                    NewRule.init env fs options
            in
            ( NewRule newRuleModel, Cmd.map NewRuleMsg cmd )

        OptionsParser.NewPackage options ->
            let
                ( newPackageModel, cmd ) =
                    NewPackage.init env
                        { fs = fs
                        , os = os
                        }
                        options
            in
            ( NewPackage newPackageModel, Cmd.map NewPackageMsg cmd )

        OptionsParser.PrepareOffline options ->
            let
                ( prepareOfflineModel, cmd ) =
                    PrepareOffline.init env
                        { fs = fs
                        , os = os
                        }
                        options
            in
            ( PrepareOffline prepareOfflineModel, Cmd.map PrepareOfflineMsg cmd )


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
                    let
                        ( newReviewModel, cmd ) =
                            Review.update reviewMsg reviewModel
                    in
                    ( Review newReviewModel
                    , Cmd.map ReviewMsg cmd
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

        NewPackageMsg newPackageMsg ->
            case model of
                NewPackage newPackageModel ->
                    ( model
                    , NewPackage.update newPackageMsg newPackageModel
                        |> Cmd.map NewPackageMsg
                    )

                _ ->
                    ( model, Cmd.none )

        NewRuleMsg newRuleMsg ->
            case model of
                NewRule newRuleModel ->
                    ( model
                    , NewRule.update newRuleMsg newRuleModel
                        |> Cmd.map NewRuleMsg
                    )

                _ ->
                    ( model, Cmd.none )

        PrepareOfflineMsg prepareOfflineMsg ->
            case model of
                PrepareOffline prepareOfflineModel ->
                    ( model
                    , PrepareOffline.update prepareOfflineMsg prepareOfflineModel
                        |> Cmd.map PrepareOfflineMsg
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

        Err (FsData.NotFound _) ->
            ( Done
            , { title = "COULD NOT FIND ELM.JSON"
              , message =
                    \c ->
                        "I was expecting to find an " ++ c YellowBright "elm.json" ++ """ file in the current directory or one of its parents, but I did not find one.

If you wish to run elm-review from outside your project,
try re-running it with """ ++ c Cyan "--elmjson <path-to-elm.json>" ++ "."
              }
                |> Problem.from Problem.Recoverable
                |> Problem.stop loading.env.stderr loading.formatOptions
            )

        Err error ->
            ( Done
            , Problem.unexpectedError "when trying to find your project root" (FsExtra.errorToString error)
                |> Problem.stop loading.env.stderr loading.formatOptions
            )


findNearestElmJson : Array String -> TTask FsError Path
findNearestElmJson fs pathSegments =
    if Array.isEmpty pathSegments then
        TTask.fail (FsData.NotFound "")

    else
        let
            path : Path
            path =
                -- TODO Does this work for Windows?
                Array.push "elm.json" pathSegments |> Array.toList |> String.join "/"
        in
        Fs.stat fs path
            |> TTask.map (\_ -> path)
            |> TTask.onError
                (\_ ->
                    findNearestElmJson fs (Array.slice 0 -1 pathSegments)
                )


getCwd : Dict String String -> TTask FsError Path
getCwd env =
    -- TODO Replace this by the following when fixed.
    -- Fs.toSandboxRel fs path "."
    case Dict.get "PWD" env of
        Just path ->
            TTask.succeed path

        Nothing ->
            TTask.fail (FsData.NotFound ".")


subscriptions : Model -> Sub Msg
subscriptions model =
    case model of
        Review reviewModel ->
            Review.subscriptions reviewModel
                |> Sub.map ReviewMsg

        _ ->
            Sub.none

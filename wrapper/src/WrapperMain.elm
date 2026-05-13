module WrapperMain exposing (Model, Msg, init, subscriptions, update)

import Array exposing (Array)
import Dict exposing (Dict)
import Elm.Review.CliVersion as CliVersion
import Elm.Review.InitError as InitError exposing (InitError)
import Elm.Review.Testable.Cli as Cli
import Elm.Review.Testable.Cmd as TCmd
import Elm.Review.Testable.Fs as Fs
import Elm.Review.Testable.FsData as FsData exposing (FsError)
import Elm.Review.Testable.Internal exposing (TCmd)
import Elm.Review.Testable.TSub as TSub exposing (TSub)
import Elm.Review.Testable.TTask as TTask exposing (TTask)
import ElmReview.Color exposing (Color(..))
import ElmReview.Path exposing (Path)
import ElmReview.Problem as Problem exposing (FormatOptions)
import ElmRun.FsExtra as FsExtra
import Wrapper.Help as Help
import Wrapper.Init as Init
import Wrapper.NewPackage as NewPackage
import Wrapper.NewRule as NewRule
import Wrapper.Options.Parser as OptionsParser
import Wrapper.OutputTarget as OutputTarget
import Wrapper.PrepareOffline as PrepareOffline
import Wrapper.Review as Review


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
    , stdinSupported : Bool
    }


type Msg
    = FoundNearestElmJson (Result FsError Path)
    | ReviewMsg Review.Msg
    | InitMsg Init.Msg
    | NewRuleMsg NewRule.Msg
    | NewPackageMsg NewPackage.Msg
    | PrepareOfflineMsg PrepareOffline.Msg


init : Dict String String -> List String -> Bool -> InitError ( Model, TCmd Msg )
init env args stdinSupported =
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
    OptionsParser.parse { args = args, env = env }
        binaryRoot
        elmHomePath
        OutputTarget.JavaScriptTarget
        |> handleCliArgsParseResult env stdinSupported


handleCliArgsParseResult : Dict String String -> Bool -> OptionsParser.OptionsParseResult -> InitError ( Model, TCmd Msg )
handleCliArgsParseResult env stdinSupported result =
    case result of
        OptionsParser.ParseError formatOptions problem ->
            InitError.Problem formatOptions problem

        OptionsParser.ShowHelp options ->
            ( Done
            , TCmd.batch
                [ Cli.printlnStdout (Help.show options)
                , Cli.exit 0
                ]
            )
                |> InitError.Success

        OptionsParser.ShowVersion ->
            ( Done
            , TCmd.batch
                [ Cli.printlnStdout CliVersion.version
                , Cli.exit 0
                ]
            )
                |> InitError.Success

        OptionsParser.NeedElmJsonPath { formatOptions, toOptions } ->
            ( Loading
                { env = env
                , formatOptions = formatOptions
                , toOptions = toOptions
                , stdinSupported = stdinSupported
                }
            , getCwd env
                |> TTask.andThen
                    (\cwd ->
                        -- TODO Use `\` for Windows Support?
                        String.split "/" cwd
                            |> Array.fromList
                            |> findNearestElmJson
                    )
                |> TTask.attempt FoundNearestElmJson
            )
                |> InitError.Success

        OptionsParser.Review options ->
            let
                ( review, cmd ) =
                    Review.init options
            in
            ( Review review, TCmd.map ReviewMsg cmd )
                |> InitError.Success

        OptionsParser.Init options ->
            let
                ( initModel, cmd ) =
                    Init.init stdinSupported options
            in
            ( Init initModel, TCmd.map InitMsg cmd )
                |> InitError.Success

        OptionsParser.NewRule options ->
            let
                ( newRuleModel, cmd ) =
                    NewRule.init stdinSupported options
            in
            ( NewRule newRuleModel, TCmd.map NewRuleMsg cmd )
                |> InitError.Success

        OptionsParser.NewPackage options ->
            let
                ( newPackageModel, cmd ) =
                    NewPackage.init stdinSupported options
            in
            ( NewPackage newPackageModel, TCmd.map NewPackageMsg cmd )
                |> InitError.Success

        OptionsParser.PrepareOffline options ->
            let
                ( prepareOfflineModel, cmd ) =
                    PrepareOffline.init options
            in
            ( PrepareOffline prepareOfflineModel, TCmd.map PrepareOfflineMsg cmd )
                |> InitError.Success


update : Msg -> Model -> ( Model, TCmd Msg )
update msg model =
    case msg of
        FoundNearestElmJson result ->
            case model of
                Loading loading ->
                    case foundNearestElmJson loading result of
                        InitError.Success modelAndCmd ->
                            modelAndCmd

                        InitError.Problem formatOptions problem ->
                            ( model, Problem.stop formatOptions problem )

                        InitError.StringProblem string ->
                            ( model
                            , TCmd.batch
                                [ Cli.printlnStdout string
                                , Cli.exit 1
                                ]
                            )

                _ ->
                    ( model, TCmd.none )

        ReviewMsg reviewMsg ->
            case model of
                Review reviewModel ->
                    let
                        ( newReviewModel, cmd ) =
                            Review.update reviewMsg reviewModel
                    in
                    ( Review newReviewModel
                    , TCmd.map ReviewMsg cmd
                    )

                _ ->
                    ( model, TCmd.none )

        InitMsg initMsg ->
            case model of
                Init initModel ->
                    ( model
                    , Init.update initMsg initModel
                        |> TCmd.map InitMsg
                    )

                _ ->
                    ( model, TCmd.none )

        NewPackageMsg newPackageMsg ->
            case model of
                NewPackage newPackageModel ->
                    ( model
                    , NewPackage.update newPackageMsg newPackageModel
                        |> TCmd.map NewPackageMsg
                    )

                _ ->
                    ( model, TCmd.none )

        NewRuleMsg newRuleMsg ->
            case model of
                NewRule newRuleModel ->
                    ( model
                    , NewRule.update newRuleMsg newRuleModel
                        |> TCmd.map NewRuleMsg
                    )

                _ ->
                    ( model, TCmd.none )

        PrepareOfflineMsg prepareOfflineMsg ->
            case model of
                PrepareOffline prepareOfflineModel ->
                    ( model
                    , PrepareOffline.update prepareOfflineMsg prepareOfflineModel
                        |> TCmd.map PrepareOfflineMsg
                    )

                _ ->
                    ( model, TCmd.none )


foundNearestElmJson : LoadingModel -> Result FsError Path -> InitError ( Model, TCmd Msg )
foundNearestElmJson loading result =
    case result of
        Ok elmJsonPath ->
            handleCliArgsParseResult
                loading.env
                loading.stdinSupported
                (loading.toOptions { elmJsonPath = elmJsonPath })

        Err (FsData.NotFound _) ->
            { title = "COULD NOT FIND ELM.JSON"
            , message =
                \c ->
                    "I was expecting to find an " ++ c YellowBright "elm.json" ++ """ file in the current directory or one of its parents, but I did not find one.

If you wish to run elm-review from outside your project,
try re-running it with """ ++ c Cyan "--elmjson <path-to-elm.json>" ++ "."
            }
                |> Problem.from Problem.Recoverable
                |> InitError.Problem loading.formatOptions

        Err error ->
            Problem.unexpectedError "when trying to find your project root" (FsData.errorToString error)
                |> InitError.Problem loading.formatOptions


findNearestElmJson : Array String -> TTask FsError Path
findNearestElmJson pathSegments =
    if Array.isEmpty pathSegments then
        TTask.fail (FsData.NotFound "")

    else
        let
            path : Path
            path =
                -- TODO Does this work for Windows?
                Array.push "elm.json" pathSegments |> Array.toList |> String.join "/"
        in
        Fs.stat path
            |> TTask.map (\_ -> path)
            |> TTask.onError
                (\_ ->
                    findNearestElmJson (Array.slice 0 -1 pathSegments)
                )


getCwd : Dict String String -> TTask FsError Path
getCwd env =
    -- TODO Replace this by the following when fixed.
    -- Fs.toSandboxRel  path "."
    case Dict.get "PWD" env of
        Just path ->
            TTask.succeed path

        Nothing ->
            TTask.fail (FsData.NotFound ".")


subscriptions : Model -> TSub Msg
subscriptions model =
    case model of
        Review reviewModel ->
            Review.subscriptions reviewModel
                |> TSub.map ReviewMsg

        _ ->
            TSub.none

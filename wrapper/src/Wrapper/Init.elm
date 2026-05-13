module Wrapper.Init exposing
    ( Model, init
    , Msg, update
    )

{-|

@docs Model, init
@docs Msg, update

-}

import Capabilities exposing (Console, Stdin)
import Elm.Project
import Elm.Review.Testable.Cli as Cli
import Elm.Review.Testable.Cmd as TCmd
import Elm.Review.Testable.Fs as Fs
import Elm.Review.Testable.FsData as FsData
import Elm.Review.Testable.Internal exposing (TCmd, TTask)
import Elm.Review.Testable.ProcessData as ProcessData
import Elm.Review.Testable.TTask as TTask
import ElmReview.Color as Color exposing (Color(..), Colorize)
import ElmReview.Path as Path exposing (Path)
import ElmReview.Problem as Problem exposing (Problem)
import ElmReview.ReportMode as ReportMode
import ElmRun.ElmBinary as ElmBinary
import ElmRun.FsExtra as FsExtra
import ElmRun.ProcessExtra as ProcessExtra
import ElmRun.Prompt as Prompt
import Json.Decode as Decode
import Wrapper.FetchRemoteTemplate as FetchRemoteTemplate
import Wrapper.MinVersion as MinVersion
import Wrapper.Options as Options exposing (InitOptions)
import Wrapper.RemoteTemplate exposing (RemoteTemplate)
import Wrapper.ReviewConfigTemplate as ReviewConfigTemplate


type Model
    = Model ModelData


type alias ModelData =
    { stdin : Maybe Stdin
    , options : InitOptions
    }


type Msg
    = PromptMsg Prompt.Msg
    | CreatedFiles (Result Problem ())


init : Maybe Stdin -> InitOptions -> ( Model, TCmd Msg )
init stdin options =
    let
        model : ModelData
        model =
            { stdin = stdin
            , options = options
            }
    in
    ( Model model
    , case stdin of
        Just stdin_ ->
            case options.remoteTemplate of
                Just _ ->
                    -- Don't prompt when using template, the user likely knows what they are doing.
                    createConfiguration model.options

                Nothing ->
                    prompt stdin_ model

        Nothing ->
            -- If there is no stdin, assume the prompt answer is yes.
            createConfiguration model.options
    )


update : Msg -> Model -> TCmd Msg
update msg (Model model) =
    case msg of
        PromptMsg promptMsg ->
            case Prompt.update promptMsg of
                Prompt.Accepted ->
                    createConfiguration model.options

                Prompt.Refused ->
                    Cli.exit 0

                Prompt.TriggerCmd cmd ->
                    TCmd.map PromptMsg cmd

        CreatedFiles (Ok ()) ->
            TCmd.batch
                [ Cli.printlnStdout (successMessage model.options)
                , Cli.exit 0
                ]

        CreatedFiles (Err problem) ->
            Problem.stop
                { color = model.options.color
                , reportMode = ReportMode.HumanReadable
                , debug = model.options.debug
                , attemptFutureRecovery = False
                }
                problem


prompt : Stdin -> ModelData -> TCmd Msg
prompt stdin model =
    Prompt.prompt stdin
        { color = model.options.color
        , priorMessage = Nothing
        , question =
            \c ->
                let
                    path : Path
                    path =
                        -- TODO Anonymize?
                        model.options.configPath
                in
                "Would you like me to create " ++ c Yellow "elm.json" ++ " and " ++ c Yellow "src/ReviewConfig.elm" ++ " inside " ++ c Yellow path ++ "?"
        }
        |> TCmd.map PromptMsg


createConfiguration : InitOptions -> TCmd Msg
createConfiguration options =
    case options.remoteTemplate of
        Nothing ->
            createDefaultConfiguration options.configPath
                |> TTask.attempt CreatedFiles

        Just remoteTemplate ->
            createTemplateConfiguration options.configPath options.offline remoteTemplate options.debug
                |> TTask.attempt CreatedFiles


createDefaultConfiguration : Path -> TTask Problem ()
createDefaultConfiguration reviewPath =
    ElmBinary.findElmVersion
        |> TTask.andThen (\elmVersion -> ReviewConfigTemplate.create elmVersion reviewPath Nothing)
        |> TTask.mapError (\error -> Problem.unexpectedError "while creating files" (FsExtra.errorToString error))


createTemplateConfiguration : Path -> Bool -> RemoteTemplate -> Bool -> TTask Problem ()
createTemplateConfiguration reviewPath offline remoteTemplate debug =
    FetchRemoteTemplate.checkoutGitRepository offline remoteTemplate debug
        |> TTask.andThen
            (\templateConfigPath ->
                let
                    elmJsonPath : Path
                    elmJsonPath =
                        Path.join2 templateConfigPath "elm.json"
                in
                Fs.readTextFile elmJsonPath
                    |> TTask.mapError
                        (\error ->
                            case error of
                                FsData.NotFound _ ->
                                    elmJsonNotFoundProblem remoteTemplate

                                FsData.PermissionDenied ->
                                    Problem.unexpectedError ("when trying to read " ++ elmJsonPath) "Permission denied."

                                FsData.IoError message ->
                                    Problem.unexpectedError ("when trying to read " ++ elmJsonPath) message
                                        |> Problem.withPath elmJsonPath
                        )
                    |> TTask.andThen
                        (\rawElmJson ->
                            parseElmJson remoteTemplate elmJsonPath rawElmJson
                                |> TTask.fromResult
                                |> TTask.andThen
                                    (\elmJson ->
                                        TTask.map2
                                            (\() () -> ())
                                            (Fs.writeTextFile (Path.join2 reviewPath "elm.json") rawElmJson
                                                |> TTask.mapError (\error -> Problem.unexpectedError "writing the template's elm.json file" (FsExtra.errorToString error))
                                            )
                                            (TTask.mapAllAndIgnore
                                                (\directory ->
                                                    Fs.copyDirectory
                                                        { from = Path.join2 templateConfigPath directory
                                                        , to = Path.join2 reviewPath directory
                                                        }
                                                        |> TTask.mapError
                                                            (\error ->
                                                                let
                                                                    stepDescription : String
                                                                    stepDescription =
                                                                        "copying the template's " ++ directory ++ " source directory"
                                                                in
                                                                case error of
                                                                    ProcessData.ProcessRunError processError ->
                                                                        Problem.unexpectedError stepDescription (ProcessExtra.errorToString processError)

                                                                    ProcessData.CommandNotFound ->
                                                                        Problem.unexpectedError stepDescription "Command `cp` not found"

                                                                    ProcessData.CommandFailed completed ->
                                                                        Problem.unexpectedError stepDescription (Maybe.withDefault "No output." completed.stderr)
                                                            )
                                                )
                                                elmJson.dirs
                                            )
                                    )
                        )
            )


elmJsonNotFoundProblem : RemoteTemplate -> Problem
elmJsonNotFoundProblem remoteTemplate =
    -- TODO Duplicated in Build. More code sharing?
    let
        elmJsonPath : Path
        elmJsonPath =
            Path.join2 (Maybe.withDefault "." remoteTemplate.pathToFolder) "elm.json"
    in
    { title = "TEMPLATE ELM.JSON NOT FOUND"
    , message =
        \c -> "I found the " ++ c Yellow remoteTemplate.repoName ++ """ repository on GitHub,
but I could not find a """ ++ c Yellow elmJsonPath ++ """ file in it.

I need this file to determine the rest of the configuration."""
    }
        |> Problem.from Problem.Unrecoverable


parseElmJson : RemoteTemplate -> String -> String -> Result Problem Elm.Project.ApplicationInfo
parseElmJson remoteTemplate elmJsonPath rawElmJson =
    -- TODO This is quite a bit of duplication with Build.parseElmJson. Could we share some of the code?
    case Decode.decodeString Elm.Project.decoder rawElmJson of
        Err error ->
            Err (Problem.invalidElmJson elmJsonPath (Options.Remote remoteTemplate) error)

        Ok (Elm.Project.Package _) ->
            let
                referenceAsUrl : String
                referenceAsUrl =
                    case remoteTemplate.reference of
                        Just ref ->
                            "#" ++ ref

                        Nothing ->
                            ""
            in
            { title = "INVALID TEMPLATE ELM.JSON TYPE"
            , message =
                \c ->
                    "I found the " ++ c Yellow "elm.json" ++ " associated with " ++ c Yellow remoteTemplate.repoName ++ """ repository on GitHub,
but it is of type """ ++ c Red "package" ++ " when I need it to be of type " ++ c Yellow "application" ++ """.

Maybe you meant to target the """ ++ c Cyan "example" ++ " or the " ++ c Cyan "preview" ++ """ folder in that repository?

    elm-review --template """ ++ remoteTemplate.repoName ++ "/example" ++ referenceAsUrl ++ """
    elm-review --template """ ++ remoteTemplate.repoName ++ "/review" ++ referenceAsUrl
            }
                |> Problem.from Problem.Unrecoverable
                |> Err

        Ok (Elm.Project.Application application) ->
            -- TODO Upgrade dependencies if the major versions match
            case MinVersion.validateDependencyVersion (Options.Remote remoteTemplate) Nothing application of
                Err problem ->
                    problem
                        |> Problem.from Problem.Unrecoverable
                        |> Problem.withPath elmJsonPath
                        |> Err

                Ok _ ->
                    Ok application


successMessage : InitOptions -> String
successMessage options =
    let
        c : Colorize
        c =
            Color.toAnsi options.color

        path : Path
        path =
            -- TODO Anonymize?
            options.configPath

        reviewConfigPath : Path
        reviewConfigPath =
            Path.join2 path "src/ReviewConfig.elm"

        ( message, recommendation ) =
            case options.remoteTemplate of
                Nothing ->
                    ( regularInitMessage c reviewConfigPath, "" )

                Just _ ->
                    ( templateInitMessage c reviewConfigPath, templateRecommendation c )
    in
    -- TODO Support underline under following URLS
    "All done! I have created a review project at " ++ c Green path ++ """ for you.

""" ++ message ++ """

I recommend you take a look at the following documents:
  - How to configure """ ++ c Cyan "elm-review" ++ """: https://github.com/jfmengels/elm-review/#Configuration
  - When to write or enable a rule: https://github.com/jfmengels/elm-review/#when-to-write-or-enable-a-rule
""" ++ recommendation


regularInitMessage : Colorize -> Path -> String
regularInitMessage c reviewConfigPath =
    "You can now define your review configuration by editing " ++ c Green reviewConfigPath ++ "."


templateInitMessage : Colorize -> Path -> String
templateInitMessage c reviewConfigPath =
    """You chose to use someone's review configuration which can be great to get started
but don't forget to review the configuration to make sure it fits your needs,
both by removing rules you disagree with and by finding new rules to aid you.
You can do so by editing """ ++ c Green reviewConfigPath ++ "."


templateRecommendation : Colorize -> String
templateRecommendation c =
    """
By starting out with this configuration, you may end up with too many errors to handle at once.
I recommend you use a mix of the following approaches:
  - Enable rules one by one by commenting them out at first
  - Use """ ++ c Orange "elm-review suppress" ++ " to suppress existing errors but prevent future ones (see " ++ c Orange "elm-review suppress --help" ++ ")."

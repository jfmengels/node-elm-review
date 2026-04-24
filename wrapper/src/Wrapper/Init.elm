module Wrapper.Init exposing
    ( Model, init
    , Msg, update
    )

{-|

@docs Model, init
@docs Msg, update

-}

import Capabilities exposing (Console, Stdin)
import Cli
import Elm.Project
import ElmReview.Color as Color exposing (Color(..), Colorize)
import ElmReview.Path as Path exposing (Path)
import ElmReview.Problem as Problem exposing (Problem)
import ElmReview.ReportMode as ReportMode
import ElmRun.ElmBinary as ElmBinary
import ElmRun.FsExtra as FsExtra
import ElmRun.OsExtra as OsExtra
import ElmRun.Prompt as Prompt
import ElmRun.TaskExtra as TaskExtra
import Fs exposing (FileSystem, FsError)
import Json.Decode as Decode
import Os exposing (ProcessCapability)
import Task exposing (Task)
import Wrapper.FetchRemoteTemplate as FetchRemoteTemplate
import Wrapper.MinVersion as MinVersion
import Wrapper.Options as Options exposing (InitOptions)
import Wrapper.RemoteTemplate exposing (RemoteTemplate)
import Wrapper.ReviewConfigTemplate as ReviewConfigTemplate


type Model
    = Model ModelData


type alias ModelData =
    { stdout : Console
    , stderr : Console
    , stdin : Maybe Stdin
    , fs : FileSystem
    , os : ProcessCapability
    , options : InitOptions
    }


type Msg
    = PromptMsg Prompt.Msg
    | CreatedFiles (Result Problem ())


init : { env | stdout : Console, stderr : Console, stdin : Maybe Stdin } -> { capabilities | fs : FileSystem, os : ProcessCapability } -> InitOptions -> ( Model, Cmd Msg )
init { stdout, stderr, stdin } { fs, os } options =
    let
        model : ModelData
        model =
            { stdout = stdout
            , stderr = stderr
            , stdin = stdin
            , fs = fs
            , os = os
            , options = options
            }
    in
    ( Model model
    , case stdin of
        Just stdin_ ->
            case options.remoteTemplate of
                Just _ ->
                    -- Don't prompt when using template, the user likely knows what they are doing.
                    createConfiguration fs os model.options

                Nothing ->
                    prompt stdin_ model

        Nothing ->
            -- If there is no stdin, assume the prompt answer is yes.
            createConfiguration fs os model.options
    )


update : Msg -> Model -> Cmd Msg
update msg (Model model) =
    case msg of
        PromptMsg promptMsg ->
            case Prompt.update promptMsg of
                Prompt.Accepted ->
                    createConfiguration model.fs model.os model.options

                Prompt.Refused ->
                    Cli.exit 0

                Prompt.TriggerCmd cmd ->
                    Cmd.map PromptMsg cmd

        CreatedFiles (Ok ()) ->
            Cmd.batch
                [ Cli.println model.stdout (successMessage model.options)
                , Cli.exit 0
                ]

        CreatedFiles (Err problem) ->
            Problem.exit model.stderr
                { color = model.options.color
                , reportMode = ReportMode.HumanReadable
                , debug = model.options.debug
                }
                problem


prompt : Stdin -> ModelData -> Cmd Msg
prompt stdin model =
    Prompt.prompt stdin
        model.stdout
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
        |> Cmd.map PromptMsg


createConfiguration : FileSystem -> ProcessCapability -> InitOptions -> Cmd Msg
createConfiguration fs os options =
    case options.remoteTemplate of
        Nothing ->
            createDefaultConfiguration fs os options.configPath
                |> Task.attempt CreatedFiles

        Just remoteTemplate ->
            createTemplateConfiguration fs os options.configPath remoteTemplate options.debug
                |> Task.attempt CreatedFiles


createDefaultConfiguration : FileSystem -> ProcessCapability -> Path -> Task Problem ()
createDefaultConfiguration fs os reviewPath =
    ElmBinary.findElmVersion os
        |> Task.andThen (\elmVersion -> ReviewConfigTemplate.create fs elmVersion reviewPath Nothing)
        |> Task.mapError (\error -> Problem.unexpectedError "while creating files" (FsExtra.errorToString error))


createTemplateConfiguration : FileSystem -> ProcessCapability -> Path -> RemoteTemplate -> Bool -> Task Problem ()
createTemplateConfiguration fs os reviewPath remoteTemplate debug =
    FetchRemoteTemplate.checkoutGitRepository fs os remoteTemplate debug
        |> Task.andThen
            (\templateConfigPath ->
                let
                    elmJsonPath : Path
                    elmJsonPath =
                        Path.join2 templateConfigPath "elm.json"
                in
                Fs.readTextFile fs elmJsonPath
                    |> Task.mapError
                        (\error ->
                            case error of
                                Fs.NotFound _ ->
                                    elmJsonNotFoundProblem remoteTemplate

                                Fs.PermissionDenied ->
                                    Problem.unexpectedError ("when trying to read " ++ elmJsonPath) "Permission denied."

                                Fs.IoError message ->
                                    Problem.unexpectedError ("when trying to read " ++ elmJsonPath) message
                                        |> Problem.withPath elmJsonPath
                        )
                    |> Task.andThen
                        (\rawElmJson ->
                            parseElmJson remoteTemplate elmJsonPath rawElmJson
                                |> TaskExtra.resultToTask
                                |> Task.andThen
                                    (\elmJson ->
                                        Task.map2
                                            (\() () -> ())
                                            (Fs.writeTextFile fs (Path.join2 reviewPath "elm.json") rawElmJson
                                                |> Task.mapError (\error -> Problem.unexpectedError "writing the template's elm.json file" (FsExtra.errorToString error))
                                            )
                                            (TaskExtra.mapAllAndIgnore
                                                (\directory ->
                                                    FsExtra.copyDirectory os
                                                        { from = Path.join2 templateConfigPath directory
                                                        , to = Path.join2 reviewPath directory
                                                        }
                                                        |> Task.mapError (\error -> Problem.unexpectedError ("copying the template's " ++ directory ++ " source directory") (OsExtra.errorToString error))
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
        |> Problem.from


parseElmJson : RemoteTemplate -> String -> String -> Result Problem Elm.Project.ApplicationInfo
parseElmJson remoteTemplate elmJsonPath rawElmJson =
    -- TODO This is quite a bit of duplication with Build.parseElmJson. Could we share some of the code?
    -- TODO Review errors coming out of this function, especially wrt to templates
    case Decode.decodeString Elm.Project.decoder rawElmJson of
        Err error ->
            -- TODO Improve error when elm.json is from a template
            Err (Problem.invalidElmJson elmJsonPath error)

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
                |> Problem.from
                |> Err

        Ok (Elm.Project.Application application) ->
            -- TODO Upgrade dependencies if the major versions match
            case MinVersion.validateDependencyVersion (Options.Remote remoteTemplate) application of
                Just problem ->
                    problem
                        |> Problem.from
                        |> Problem.withPath elmJsonPath
                        |> Err

                Nothing ->
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

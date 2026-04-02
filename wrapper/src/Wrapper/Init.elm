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
import ElmReview.Color as Color exposing (Color(..), Colorize)
import ElmReview.Path as Path exposing (Path)
import Fs exposing (FileSystem, FsError)
import Os exposing (ProcessCapability)
import Stdin exposing (StdinError)
import Task
import Wrapper.Options exposing (InitOptions)
import Wrapper.Prompt as Prompt


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
    = UserPressedKey Stdin (Result StdinError Stdin.Key)


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
    ( Model model, prompt model )


update : Msg -> Model -> Cmd Msg
update msg (Model model) =
    case msg of
        -- TODO Figure out how to get interactive keypresses that don't wait for the Enter key
        UserPressedKey stdin (Ok key) ->
            case Prompt.interpretKey key of
                Prompt.Yes ->
                    installFiles model.options model.stdout

                Prompt.No ->
                    Cli.exit 0

                Prompt.Unknown ->
                    Stdin.readKey stdin |> Task.attempt (UserPressedKey stdin)

        UserPressedKey _ (Err err) ->
            Debug.todo ("Got error while awaiting key: " ++ Debug.toString err)


prompt : ModelData -> Cmd Msg
prompt model =
    let
        c : Colorize
        c =
            Color.toAnsi model.options.color

        path : Path
        path =
            -- TODO Anonymize?
            model.options.configPath

        promptText : String
        promptText =
            -- TODO Add colors for Y/n?
            "Would you like me to create " ++ c Yellow "elm.json" ++ " and " ++ c Yellow "src/ReviewConfig.elm" ++ " inside " ++ c Yellow path ++ "? › (Y/n)"
    in
    case model.stdin of
        Just stdin ->
            Cmd.batch
                [ Cli.println model.stdout promptText
                , Stdin.readKey stdin |> Task.attempt (UserPressedKey stdin)
                ]

        Nothing ->
            -- If there is no stdin, assume the answer is yes.
            installFiles model.options model.stdout


installFiles : InitOptions -> Console -> Cmd msg
installFiles options stdout =
    Cmd.batch
        [ Cli.println stdout (successMessage options)
        , Cli.exit 0
        ]


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
            case options.template of
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

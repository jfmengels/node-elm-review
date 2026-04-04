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
import Elm.Version exposing (Version)
import ElmReview.Color as Color exposing (Color(..), Colorize)
import ElmReview.Path as Path exposing (Path)
import ElmRun.ElmBinary as ElmBinary
import ElmRun.FsExtra as FsExtra
import ElmRun.OsExtra as OsExtra
import Fs exposing (FileSystem, FsError)
import Os exposing (ProcessCapability)
import Platform exposing (Task)
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
    | CreatedFiles (Result String ())


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
                    installFiles fs os model.options.configPath

                Nothing ->
                    prompt stdin_ model

        Nothing ->
            -- If there is no stdin, assume the prompt answer is yes.
            installFiles fs os model.options.configPath
    )


update : Msg -> Model -> Cmd Msg
update msg (Model model) =
    case msg of
        -- TODO Figure out how to get interactive keypresses that don't wait for the Enter key
        UserPressedKey stdin (Ok key) ->
            case Prompt.interpretKey key of
                Prompt.Yes ->
                    installFiles model.fs model.os model.options.configPath

                Prompt.No ->
                    Cli.exit 0

                Prompt.Unknown ->
                    Stdin.readKey stdin |> Task.attempt (UserPressedKey stdin)

        UserPressedKey _ (Err err) ->
            Debug.todo ("Got error while awaiting key: " ++ Debug.toString err)

        CreatedFiles (Ok ()) ->
            Cmd.batch
                [ Cli.println model.stdout (successMessage model.options)
                , Cli.exit 0
                ]

        CreatedFiles (Err err) ->
            Debug.todo ("Got error while creating files: " ++ err)


prompt : Stdin -> ModelData -> Cmd Msg
prompt stdin model =
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
    Cmd.batch
        [ Cli.println model.stdout promptText
        , Stdin.readKey stdin |> Task.attempt (UserPressedKey stdin)
        ]


installFiles : FileSystem -> ProcessCapability -> Path -> Cmd Msg
installFiles fs os reviewPath =
    let
        reviewSrcPath : Path
        reviewSrcPath =
            Path.join2 reviewPath "src"
    in
    Fs.createDirectory fs reviewSrcPath
        |> Task.mapError FsExtra.errorToString
        |> Task.andThen
            (\() ->
                Task.map2 (\_ _ -> ())
                    (createElmJson fs os reviewPath
                        |> Task.mapError FsExtra.errorToString
                    )
                    (FsExtra.copyFile os
                        { from = initTemplatePath "DefaultReviewConfig.elm"
                        , to = Path.join2 reviewSrcPath "ReviewConfig.elm"
                        }
                        |> Task.mapError OsExtra.errorToString
                    )
            )
        |> Task.attempt CreatedFiles


createElmJson : FileSystem -> ProcessCapability -> Path -> Task FsError ()
createElmJson fs os reviewPath =
    ElmBinary.findElmVersion os
        |> Task.andThen
            (\elmVersion ->
                Fs.writeTextFile
                    fs
                    (Path.join2 reviewPath "elm.json")
                    (createNewReviewElmJson elmVersion)
            )


createNewReviewElmJson : Version -> String
createNewReviewElmJson elmVersion =
    -- TODO Update dependencies to the latest version
    -- Maybe avoid this when options.forTests == True
    -- and have a test just checking that without tests the elm.json file is different but valid?
    -- TODO Make sure jfmengels/elm-review is always at least MinVersion.supportedRange
    """{
    "type": "application",
    "source-directories": [
        "src"
    ],
    "elm-version": \"""" ++ Elm.Version.toString elmVersion ++ """",
    "dependencies": {
        "direct": {
            "elm/core": "1.0.5",
            "jfmengels/elm-review": "2.16.6",
            "stil4m/elm-syntax": "7.3.9"
        },
        "indirect": {
            "elm/bytes": "1.0.8",
            "elm/html": "1.0.1",
            "elm/json": "1.1.4",
            "elm/parser": "1.1.0",
            "elm/project-metadata-utils": "1.0.2",
            "elm/random": "1.0.0",
            "elm/regex": "1.0.0",
            "elm/time": "1.0.0",
            "elm/virtual-dom": "1.0.5",
            "elm-explorations/test": "2.2.1",
            "rtfeldman/elm-hex": "1.0.0",
            "stil4m/structured-writer": "1.0.3"
        }
    },
    "test-dependencies": {
        "direct": {
            "elm-explorations/test": "2.2.1"
        },
        "indirect": {}
    }
}
"""


initTemplatePath : Path -> Path
initTemplatePath templatePath =
    Path.join2
        -- TODO Use path relative to this binary
        "/Users/m1/dev/node-elm-review/init-templates"
        templatePath


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

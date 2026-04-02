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
import ElmReview.Path exposing (Path)
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
                    installFiles model.stdout

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
            installFiles model.stdout


installFiles : Console -> Cmd msg
installFiles stdout =
    Cmd.batch
        [ Cli.println stdout "Installing"
        , Cli.exit 0
        ]

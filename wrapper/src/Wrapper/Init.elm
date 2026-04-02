module Wrapper.Init exposing
    ( Model, init
    , Msg, update
    )

{-|

@docs Model, init
@docs Msg, update

-}

import Capabilities exposing (Console)
import Cli
import ElmReview.Color as Color exposing (Color(..), Colorize)
import ElmReview.Path exposing (Path)
import Fs exposing (FileSystem, FsError)
import Os exposing (ProcessCapability)
import Wrapper.Options exposing (InitOptions)


type Model
    = Model ModelData


type alias ModelData =
    { stdout : Console
    , stderr : Console
    , fs : FileSystem
    , os : ProcessCapability
    , options : InitOptions
    }


type Msg
    = Noop


init : { env | stdout : Console, stderr : Console } -> { capabilities | fs : FileSystem, os : ProcessCapability } -> InitOptions -> ( Model, Cmd Msg )
init { stdout, stderr } { fs, os } options =
    let
        model : ModelData
        model =
            { stdout = stdout
            , stderr = stderr
            , fs = fs
            , os = os
            , options = options
            }
    in
    ( Model model, prompt model )


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
            "Would you like me to create " ++ c Yellow "elm.json" ++ " and " ++ c Yellow "src/ReviewConfig.elm" ++ " inside " ++ c Yellow path ++ "?"
    in
    Cmd.batch
        [ Cli.println model.stdout promptText
        , Cli.exit 0
        ]


update : Msg -> Model -> Cmd Msg
update Noop _ =
    Cmd.none

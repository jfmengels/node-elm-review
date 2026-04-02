module Wrapper.Init exposing
    ( Model, init
    , Msg, update
    )

{-|

@docs Model, init
@docs Msg, update

-}

import Capabilities exposing (Console)
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
    ( Model
        { stdout = stdout
        , stderr = stderr
        , fs = fs
        , os = os
        , options = options
        }
    , Debug.todo "init command not yet implemented"
    )


update : Msg -> Model -> Cmd Msg
update Noop _ =
    Cmd.none

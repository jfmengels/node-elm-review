module ElmRun.WrapperMain exposing (main)

import ElmReview.Path exposing (Path)
import ElmRun.Program as ElmRunProgram
import Wrapper.OutputTarget as OutputTarget
import WrapperApp


main : ElmRunProgram.Program WrapperApp.Model WrapperApp.Msg
main =
    ElmRunProgram.program
        { init =
            \{ env, args, stdinSupported } ->
                let
                    -- TODO Get binaryRoot path from somewhere
                    binaryRoot : Path
                    binaryRoot =
                        "/Users/m1/dev/node-elm-review"

                    -- TODO Get userHome from somewhere
                    userHome : String
                    userHome =
                        "/Users/m1"
                in
                WrapperApp.init
                    { env = env
                    , args = args
                    , stdinSupported = stdinSupported
                    , defaultOutputTarget = OutputTarget.ElmRunTarget
                    , binaryRoot = binaryRoot
                    , userHome = userHome
                    }
        , update = WrapperApp.update
        , subscriptions = WrapperApp.subscriptions
        }

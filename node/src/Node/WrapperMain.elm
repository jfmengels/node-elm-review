module Node.WrapperMain exposing (main)

import Node.Program
import Wrapper.OutputTarget as OutputTarget
import WrapperApp


main : Node.Program.Program WrapperApp.Model WrapperApp.Msg
main =
    Node.Program.program
        { init =
            \{ env, args, binaryRoot, userHome } ->
                WrapperApp.init
                    { env = env
                    , args = args
                    , stdinSupported = True
                    , defaultOutputTarget = OutputTarget.JavaScriptTarget
                    , binaryRoot = binaryRoot
                    , userHome = userHome
                    }
        , update = WrapperApp.update
        , subscriptions = WrapperApp.subscriptions
        }

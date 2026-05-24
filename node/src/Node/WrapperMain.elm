module Node.WrapperMain exposing (main)

import Node.Program
import Wrapper.OutputTarget as OutputTarget
import WrapperMain


main : Node.Program.Program WrapperMain.Model WrapperMain.Msg
main =
    Node.Program.program
        { init =
            \{ env, args, binaryRoot, userHome } ->
                WrapperMain.init
                    { env = env
                    , args = args
                    , stdinSupported = True
                    , defaultOutputTarget = OutputTarget.JavaScriptTarget
                    , binaryRoot = binaryRoot
                    , userHome = userHome
                    }
        , update = WrapperMain.update
        , subscriptions = WrapperMain.subscriptions
        }

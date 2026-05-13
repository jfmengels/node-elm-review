module Node.WrapperMain exposing (main)

import Node.Program
import WrapperMain


main : Node.Program.Program WrapperMain.Model WrapperMain.Msg
main =
    Node.Program.program
        { init = \{ env, args, stdinSupported } -> WrapperMain.init env args stdinSupported
        , update = WrapperMain.update
        , subscriptions = WrapperMain.subscriptions
        }

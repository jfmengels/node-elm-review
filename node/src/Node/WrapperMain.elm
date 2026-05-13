module Node.WrapperMain exposing (main)

import Node.Program
import Wrapper.OutputTarget as OutputTarget
import WrapperMain


main : Node.Program.Program WrapperMain.Model WrapperMain.Msg
main =
    Node.Program.program
        { init = \{ env, args } -> WrapperMain.init env args True OutputTarget.JavaScriptTarget
        , update = WrapperMain.update
        , subscriptions = WrapperMain.subscriptions
        }

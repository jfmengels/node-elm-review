module ElmRun.WrapperMain exposing (main)

import ElmRun.Program as ElmRunProgram
import WrapperMain


main : ElmRunProgram.Program WrapperMain.Model WrapperMain.Msg
main =
    ElmRunProgram.program
        { init = \{ env, args, stdinSupported } -> WrapperMain.init env args stdinSupported
        , update = WrapperMain.update
        , subscriptions = WrapperMain.subscriptions
        }

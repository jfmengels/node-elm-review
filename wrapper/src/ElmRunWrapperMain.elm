module ElmRunWrapperMain exposing (main)

import Elm.Review.ElmRunProgram as ElmRunProgram
import WrapperMain


main : ElmRunProgram.Program WrapperMain.Model WrapperMain.Msg
main =
    ElmRunProgram.program
        { init = \{ env, args, stdin } -> WrapperMain.init env args stdin
        , update = WrapperMain.update
        , subscriptions = WrapperMain.subscriptions
        }

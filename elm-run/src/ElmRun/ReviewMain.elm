module ElmRun.ReviewMain exposing (main)

import Elm.Review.Main as Main
import ElmRun.Program as ElmRunProgram


main : ElmRunProgram.Program Main.Model Main.Msg
main =
    ElmRunProgram.program
        { init = \flags -> Main.init flags.stdinSupported flags.args
        , update = Main.update
        , subscriptions = Main.subscriptions
        }

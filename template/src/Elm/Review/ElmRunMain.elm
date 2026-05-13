module Elm.Review.ElmRunMain exposing (main)

import Elm.Review.ElmRunProgram as ElmRunProgram
import Elm.Review.Main as Main


main : ElmRunProgram.Program Main.Model Main.Msg
main =
    ElmRunProgram.program
        { init = Main.init
        , update = Main.update
        , subscriptions = Main.subscriptions
        }

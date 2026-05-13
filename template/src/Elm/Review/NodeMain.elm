module Elm.Review.NodeMain exposing (main)

import Elm.Review.Main as Main
import Elm.Review.NodeProgram as NodeProgram


main : NodeProgram.Program Main.Model Main.Msg
main =
    NodeProgram.program
        { init = \flags -> Main.init Nothing flags.args
        , update = Main.update
        , subscriptions = Main.subscriptions
        }

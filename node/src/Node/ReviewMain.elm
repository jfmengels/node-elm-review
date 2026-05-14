module Node.ReviewMain exposing (main)

import Elm.Review.Main as Main
import Node.Program


main : Node.Program.Program Main.Model Main.Msg
main =
    Node.Program.program
        { init = \flags -> Main.init True flags.args
        , update = Main.update
        , subscriptions = Main.subscriptions
        }

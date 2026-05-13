module Elm.Review.ElmRunMain exposing (main)

import Cli
import Elm.Review.Main as Main


main : Cli.Program Main.ModelWrapper Main.Msg
main =
    Cli.program
        { init = Main.init
        , update = Main.updateWrapper
        , subscriptions = Main.subscriptions
        }

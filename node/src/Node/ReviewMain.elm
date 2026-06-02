module Node.ReviewMain exposing (main)

import Elm.Review.ReviewApp as ReviewApp
import Node.Program


main : Node.Program.Program ReviewApp.Model ReviewApp.Msg
main =
    Node.Program.program
        { init = \flags -> ReviewApp.init True flags.communicationKey flags.args
        , update = ReviewApp.update
        , subscriptions = ReviewApp.subscriptions
        }

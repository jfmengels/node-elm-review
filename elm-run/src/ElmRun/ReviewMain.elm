module ElmRun.ReviewMain exposing (main)

import Elm.Review.ReviewApp as ReviewApp
import ElmRun.Program as ElmRunProgram


main : ElmRunProgram.Program ReviewApp.Model ReviewApp.Msg
main =
    ElmRunProgram.program
        { init = \flags -> ReviewApp.init flags.stdinSupported flags.args
        , update = ReviewApp.update
        , subscriptions = ReviewApp.subscriptions
        }

module Elm.Review.Testable.Cli exposing
    ( printlnStdout, printlnStderr
    , printlnStdoutTask, printlnStderrTask
    , exit
    )

{-|

@docs printlnStdout, printlnStderr
@docs printlnStdoutTask, printlnStderrTask
@docs exit

-}

import Elm.Review.Testable.CliData exposing (Console(..))
import Elm.Review.Testable.Internal as Internal exposing (TCmd)
import Elm.Review.Testable.TTask as TTask exposing (TTask)


printlnStdout : String -> TCmd msg
printlnStdout string =
    Internal.Println Stdout string


printlnStderr : String -> TCmd msg
printlnStderr string =
    Internal.Println Stderr string


printlnStdoutTask : String -> Internal.TTask x ()
printlnStdoutTask message =
    Internal.PrintlnTask Stdout message Internal.resultFromResult
        |> TTask.mapError Basics.never


printlnStderrTask : String -> Internal.TTask x ()
printlnStderrTask message =
    Internal.PrintlnTask Stderr message Internal.resultFromResult
        |> TTask.mapError Basics.never


exit : Int -> TCmd msg
exit =
    Internal.Exit

module Elm.Review.Testable.Cli exposing
    ( printlnStdout, printlnStderr
    , exit
    )

{-|

@docs printlnStdout, printlnStderr
@docs exit

-}

import Elm.Review.Testable.CliData exposing (Console(..))
import Elm.Review.Testable.Internal as Internal exposing (TCmd)


printlnStdout : String -> TCmd msg
printlnStdout string =
    Internal.PrintLn Stdout string


printlnStderr : String -> TCmd msg
printlnStderr string =
    Internal.PrintLn Stderr string


exit : Int -> TCmd msg
exit =
    Internal.Exit

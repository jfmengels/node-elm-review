module Wrapper.Color exposing
    ( Color(..)
    , Colorize
    , toAnsi
    )


type Color
    = Yellow
    | Magenta
    | Cyan
    | RedBright
    | GreenBright
    | BlueBright
    | MagentaBright
    | Orange


type alias Colorize =
    Color -> String -> String


toAnsi : Bool -> Color -> String -> String
toAnsi supportsColor =
    if supportsColor then
        \color str -> "\u{001B}[" ++ toAnsiColor color ++ "m" ++ str ++ "\u{001B}[39m"

    else
        \_ str -> str


toAnsiColor : Color -> String
toAnsiColor color =
    case color of
        Yellow ->
            "33"

        Magenta ->
            "35"

        Cyan ->
            "36"

        RedBright ->
            "91"

        GreenBright ->
            "92"

        BlueBright ->
            "94"

        MagentaBright ->
            "95"

        Orange ->
            "38;2;255;165;0"

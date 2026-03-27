module Wrapper.Color exposing
    ( Color(..)
    , Colorize
    , toAnsi
    )


type Color
    = Cyan
    | Orange
    | Yellow
    | Magenta
    | RedBright
    | GreenBright
    | BlueBright
    | MagentaBright


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
        Cyan ->
            "38;2;51;187;200"

        Orange ->
            "38;2;255;165;0"

        Yellow ->
            "38;2;232;195;56"

        Magenta ->
            "35"

        RedBright ->
            "91"

        GreenBright ->
            "92"

        BlueBright ->
            "94"

        MagentaBright ->
            "95"

module Wrapper.Color exposing
    ( Color(..)
    , Colorize
    , Support
    , noColors
    , supportsColor
    , toAnsi
    )

import Dict exposing (Dict)


type Color
    = Yellow
    | Green
    | Magenta
    | Cyan
    | RedBright
    | GreenBright
    | BlueBright
    | MagentaBright
    | Orange


type alias Colorize =
    Color -> String -> String


type Support
    = ColorSupport Bool


supportsColor : Dict String String -> Maybe Bool -> Support
supportsColor env forcedColorThroughOptions =
    ColorSupport <|
        case Dict.get "FORCE_COLOR" env of
            Just "0" ->
                False

            Just "false" ->
                False

            Just "" ->
                Maybe.withDefault True forcedColorThroughOptions

            Just _ ->
                True

            Nothing ->
                Maybe.withDefault True forcedColorThroughOptions


noColors : Support
noColors =
    ColorSupport False


toAnsi : Support -> Color -> String -> String
toAnsi (ColorSupport supportsColor_) =
    if supportsColor_ then
        \color str -> "\u{001B}[" ++ toAnsiColor color ++ "m" ++ str ++ "\u{001B}[39m"

    else
        \_ str -> str


toAnsiColor : Color -> String
toAnsiColor color =
    case color of
        Yellow ->
            "33"

        Green ->
            "38;2;0;128;0"

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

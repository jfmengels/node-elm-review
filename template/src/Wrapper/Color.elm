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
    (case colorFromEnvs env of
        Nothing ->
            forcedColorThroughOptions

        just ->
            just
    )
        |> Maybe.withDefault True
        |> ColorSupport


colorFromEnvs : Dict String String -> Maybe Bool
colorFromEnvs env =
    findMap
        [ ( Dict.get "FORCE_COLOR" env
          , \forceColor ->
                if String.isEmpty forceColor then
                    Nothing

                else
                    Just (forceColor /= "0" && forceColor /= "false")
          )
        , ( Dict.get "NO_COLOR" env
          , \noColor ->
                if String.isEmpty noColor then
                    Nothing

                else
                    Just False
          )
        ]


findMap : List ( Maybe String, String -> Maybe Bool ) -> Maybe Bool
findMap list =
    case list of
        [] ->
            Nothing

        ( a, check ) :: rest ->
            case Maybe.andThen check a of
                Nothing ->
                    findMap rest

                just ->
                    just


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
            "32"

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

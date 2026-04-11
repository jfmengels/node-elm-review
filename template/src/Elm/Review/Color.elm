module Elm.Review.Color exposing
    ( Color(..)
    , toHex, toAnsi
    )

{-| Terminal colors.

@docs Color
@docs toHex, toAnsi

-}


type Color
    = Blue
    | Red
    | Orange
    | Yellow
    | Green


toHex : Color -> String
toHex color =
    case color of
        Blue ->
            "#33BBC8"

        Red ->
            "#FF0000"

        Orange ->
            "#FFA500"

        Yellow ->
            "#E8C338"

        Green ->
            "#008000"


toAnsi : Bool -> Color -> String -> String
toAnsi supportsColor color str =
    if supportsColor then
        "\u{001B}[" ++ toRGB color ++ "m" ++ str ++ "\u{001B}[39m"

    else
        str


toRGB : Color -> String
toRGB color =
    case color of
        Blue ->
            "38;2;51;187;200"

        Red ->
            "38;2;255;0;0"

        Orange ->
            "38;2;255;165;0"

        Yellow ->
            "38;2;232;195;56"

        Green ->
            "38;2;0;128;0"

module Elm.Review.Text exposing
    ( Text, TextContent
    , from
    , inBlue, inRed, inYellow, inGreen, inOrange
    , withLink
    , join, simplify
    , toRecord, toAnsi
    )

{-| Represents text with some styling applied to it.

    text : List Text
    text =
        [ Text.from "My name is "
        , Text.from "John"
            |> Text.withColor
        , Text.from "."
        ]


# Definition

@docs Text, TextContent


# Constructors

@docs from


# Modifiers

@docs inBlue, inRed, inYellow, inGreen, inOrange
@docs withLink


# Working with lists

@docs join, simplify


# Access

@docs toRecord, toAnsi

-}

import Elm.Review.Color as Color exposing (Color)



-- DEFINITION


{-| Represents text with some styling applied to it.
-}
type Text
    = Text TextContent


type alias TextContent =
    { str : String
    , color : Maybe Color
    , href : Maybe String
    }



-- CONSTRUCTORS


{-| Create an unstyled `Text` from a string.
-}
from : String -> Text
from value =
    Text
        { str = value
        , color = Nothing
        , href = Nothing
        }



-- MODIFIERS


inBlue : Text -> Text
inBlue (Text text) =
    Text { str = text.str, color = Just Color.Blue, href = text.href }


inRed : Text -> Text
inRed (Text text) =
    Text { str = text.str, color = Just Color.Red, href = text.href }


inOrange : Text -> Text
inOrange (Text text) =
    Text { str = text.str, color = Just Color.Orange, href = text.href }


inYellow : Text -> Text
inYellow (Text text) =
    Text { str = text.str, color = Just Color.Yellow, href = text.href }


inGreen : Text -> Text
inGreen (Text text) =
    Text { str = text.str, color = Just Color.Green, href = text.href }


withLink : Maybe String -> Text -> Text
withLink maybeLink (Text text) =
    Text { str = text.str, color = text.color, href = maybeLink }



-- WORKING WITH LISTS


join : String -> List (List Text) -> List Text
join sep chunks =
    List.intersperse [ from sep ] chunks
        |> List.concat


simplify : List Text -> List TextContent
simplify chunks =
    case chunks of
        [] ->
            []

        (Text chunk) :: restOfChunks ->
            simplifyHelp [] chunk restOfChunks
                |> List.foldl (\x acc -> toRecord x :: acc) []


simplifyHelp : List Text -> TextContent -> List Text -> List Text
simplifyHelp previousTexts lastText chunks =
    case chunks of
        [] ->
            Text lastText :: previousTexts

        (Text newLastText) :: restOfChunks ->
            if lastText.color == newLastText.color && lastText.href == newLastText.href then
                simplifyHelp previousTexts
                    { str = lastText.str ++ newLastText.str
                    , color = lastText.color
                    , href = lastText.href
                    }
                    restOfChunks

            else
                simplifyHelp (Text lastText :: previousTexts) newLastText restOfChunks



-- ACCESS


{-| Transform a text into a record that can then be transformed for display in
different mediums.
-}
toRecord : Text -> TextContent
toRecord (Text text) =
    text


toAnsi : Bool -> List TextContent -> String
toAnsi supportsColor segments =
    if supportsColor then
        toAnsiHelp segments ""

    else
        List.map .str segments |> String.concat


toAnsiHelp : List TextContent -> String -> String
toAnsiHelp segments acc =
    case segments of
        [] ->
            acc

        { str, color, href } :: rest ->
            -- TODO Only add terminal links when supported
            let
                ansiStr : String
                ansiStr =
                    str
                        |> maybeApply (\c -> Color.toAnsi True c) color
                        |> maybeApply addLink href
            in
            toAnsiHelp rest (acc ++ ansiStr)


maybeApply : (a -> b -> b) -> Maybe a -> b -> b
maybeApply fn maybe data =
    case maybe of
        Just x ->
            fn x data

        Nothing ->
            data


addLink : String -> String -> String
addLink url text =
    "\u{001B}]8;;" ++ url ++ "\u{0007}" ++ text ++ "\u{001B}]8;;\u{0007}"

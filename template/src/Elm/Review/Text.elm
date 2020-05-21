module Elm.Review.Text exposing
    ( Text, TextContent
    , from
    , inBlue, inRed, inYellow, inGreen
    , join, simplify
    , toRecord
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

@docs inBlue, inRed, inYellow, inGreen


# Working with lists

@docs join, simplify


# Access

@docs toRecord

-}

-- DEFINITION


{-| Represents text with some styling applied to it.
-}
type Text
    = Text TextContent


type alias TextContent =
    { str : String
    , color : Maybe ( Int, Int, Int )
    , backgroundColor : Maybe ( Int, Int, Int )
    }



-- CONSTRUCTORS


{-| Create an unstyled `Text` from a string.
-}
from : String -> Text
from value =
    Text
        { str = value
        , color = Nothing
        , backgroundColor = Nothing
        }



-- MODIFIERS


inBlue : Text -> Text
inBlue (Text text) =
    Text { text | color = Just ( 51, 187, 200 ) }


inRed : Text -> Text
inRed (Text text) =
    Text { text | color = Just ( 255, 0, 0 ) }


inYellow : Text -> Text
inYellow (Text text) =
    Text { text | color = Just ( 255, 255, 0 ) }


inGreen : Text -> Text
inGreen (Text text) =
    Text { text | color = Just ( 0, 128, 0 ) }



-- WORKING WITH LISTS


join : String -> List (List Text) -> List Text
join sep chunks =
    List.intersperse [ from sep ] chunks
        |> List.concatMap identity


simplify : List Text -> List Text
simplify chunks =
    case chunks of
        [] ->
            []

        (Text chunk) :: restOfChunks ->
            simplifyHelp [] chunk restOfChunks
                |> List.reverse


simplifyHelp : List Text -> TextContent -> List Text -> List Text
simplifyHelp previousTexts lastText chunks =
    case chunks of
        [] ->
            Text lastText :: previousTexts

        (Text newLastText) :: restOfChunks ->
            if lastText.color == newLastText.color && lastText.backgroundColor == newLastText.backgroundColor then
                simplifyHelp previousTexts { lastText | str = lastText.str ++ newLastText.str } restOfChunks

            else
                simplifyHelp (Text lastText :: previousTexts) newLastText restOfChunks



-- ACCESS


{-| Transform a text into a record that can then be transformed for display in
different mediums.
-}
toRecord : Text -> TextContent
toRecord (Text text) =
    text

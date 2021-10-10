module Elm.Review.Text exposing
    ( Text, TextContent
    , from
    , inBlue, inRed, inYellow, inGreen
    , withLink
    , join, simplify
    , toRecord
    , inOrange
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
@docs withLink


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
    , color : Maybe String
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
    Text { text | color = Just "#33BBC8" }


inRed : Text -> Text
inRed (Text text) =
    Text { text | color = Just "#FF0000" }


inOrange : Text -> Text
inOrange (Text text) =
    Text { text | color = Just "#FFA500" }


inYellow : Text -> Text
inYellow (Text text) =
    Text { text | color = Just "#FFFF00" }


inGreen : Text -> Text
inGreen (Text text) =
    Text { text | color = Just "#008000" }


withLink : Maybe String -> Text -> Text
withLink maybeLink (Text text) =
    Text { text | href = maybeLink }



-- WORKING WITH LISTS


join : String -> List (List Text) -> List Text
join sep chunks =
    List.intersperse [ from sep ] chunks
        |> List.concat


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

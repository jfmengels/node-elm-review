module Elm.Review.Text exposing
    ( Text, TextContent
    , from
    , inBlue, inRed, inGreen
    , join
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

@docs inBlue, inRed, inGreen


# Working with lists

@docs join


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


inGreen : Text -> Text
inGreen (Text text) =
    Text { text | color = Just ( 0, 128, 0 ) }



-- WORKING WITH LISTS


join : String -> List (List Text) -> List Text
join sep chunks =
    List.intersperse [ from sep ] chunks
        |> List.concatMap identity



-- ACCESS


{-| Transform a text into a record that can then be transformed for display in
different mediums.
-}
toRecord : Text -> TextContent
toRecord (Text text) =
    text

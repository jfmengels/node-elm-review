module Text exposing
    ( Text
    , from
    , inGreen, inRed
    , join
    , length
    , encode
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

@docs Text


# Constructors

@docs from


# Modifiers

@docs inGreen, inRed


# Working with lists

@docs join


# ACCESS

@docs length


# Encoding

@docs encode

-}

import Json.Encode as Encode



-- DEFINITION


{-| Represents text with some styling applied to it.
-}
type Text
    = Text
        { str : String
        , color : Maybe String
        }



-- CONSTRUCTORS


{-| Create an unstyled `Text` from a string.
-}
from : String -> Text
from value =
    Text
        { str = value
        , color = Nothing
        }



-- MODIFIERS


inGreen : Text -> Text
inGreen (Text text) =
    Text { text | color = Just "green" }


inRed : Text -> Text
inRed (Text text) =
    Text { text | color = Just "red" }



-- WORKING WITH LISTS


join : String -> List (List Text) -> List Text
join sep chunks =
    List.intersperse [ from sep ] chunks
        |> List.concatMap identity



-- ACCESS


length : Text -> Int
length (Text text) =
    String.length text.str



-- ENCODING


{-| Encode texts to a JSON value.
-}
encode : List Text -> Encode.Value
encode texts =
    Encode.list encodePart texts


encodePart : Text -> Encode.Value
encodePart (Text text) =
    Encode.object
        [ ( "string", Encode.string text.str )
        , ( "color"
          , case text.color of
                Just color ->
                    Encode.string color

                Nothing ->
                    Encode.null
          )
        ]

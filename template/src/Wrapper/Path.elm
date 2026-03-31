module Wrapper.Path exposing
    ( Path
    , dirname, join, join2
    )

{-| Utilities to work with paths.

@docs Path
@docs dirname, join, join2

-}


type alias Path =
    String


dirname : Path -> Path
dirname path =
    case List.reverse (String.split "/" path) of
        [] ->
            ""

        [ _ ] ->
            "."

        _ :: rest ->
            String.join "/" (List.reverse rest)


join2 : Path -> Path -> Path
join2 a b =
    if a == "." then
        b

    else if b == "." then
        a

    else
        (String.split "/" a ++ String.split "/" b)
            |> String.join "/"


join : List Path -> Path
join list =
    List.foldr join2 "." list

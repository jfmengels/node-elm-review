module Wrapper.Path exposing
    ( Path
    , dirname, join
    )

{-| Utilities to work with paths.

@docs Path
@docs dirname, join

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


join : Path -> Path -> Path
join a b =
    if a == "." then
        b

    else if b == "." then
        a

    else
        (String.split "/" a ++ String.split "/" b)
            |> String.join "/"

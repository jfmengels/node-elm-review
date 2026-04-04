module ElmReview.Path exposing
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
    if a == "." || String.startsWith "/" b || String.startsWith "~" b then
        b

    else if b == "." then
        a

    else
        let
            prefixPath : String
            prefixPath =
                if String.startsWith "/" a then
                    "/"

                else
                    ""

            segments : List String
            segments =
                (String.split "/" a ++ String.split "/" b)
                    |> List.filter (\s -> s /= "")
        in
        prefixPath ++ String.join "/" segments


join : List Path -> Path
join list =
    List.foldr join2 "." list

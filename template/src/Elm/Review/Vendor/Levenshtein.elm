module Elm.Review.Vendor.Levenshtein exposing (distance)

{-| Levenshtein distance is a metric for measuring the difference between two strings.

@docs distance

-}

import Array exposing (Array)
import Elm.Review.Vendor.Memo as Memo


type alias Memo =
    Memo.Memo ( Int, Int )


{-| Computes the Levenshtein distance between two strings.
-}
distance : String -> String -> Int
distance str1 str2 =
    if str1 == str2 then
        0

    else
        helper
            (Array.fromList (String.toList str1))
            (Array.fromList (String.toList str2))


helper arr1 arr2 =
    let
        lev : Memo -> ( Int, Int ) -> ( Memo, Int )
        lev memo ( i, j ) =
            case ( Array.get (i - 1) arr1, Array.get (j - 1) arr2 ) of
                ( Just chr1, Just chr2 ) ->
                    let
                        indicator =
                            if chr1 /= chr2 then
                                1

                            else
                                0

                        ( memo1, dist1 ) =
                            Memo.fetch ( i - 1, j ) lev memo

                        ( memo2, dist2 ) =
                            Memo.fetch ( i, j - 1 ) lev memo1

                        ( memo3, dist3 ) =
                            Memo.fetch ( i - 1, j - 1 ) lev memo2
                    in
                    ( memo3
                    , min3
                        (dist1 + 1)
                        (dist2 + 1)
                        (dist3 + indicator)
                    )

                _ ->
                    ( memo, max i j )
    in
    lev Memo.empty ( Array.length arr1, Array.length arr2 )
        |> Tuple.second


min3 : comparable -> comparable -> comparable -> comparable
min3 a b c =
    min (min a b) c

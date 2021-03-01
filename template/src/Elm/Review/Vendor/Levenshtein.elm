module Elm.Review.Vendor.Levenshtein exposing (distance)

{-| Levenshtein distance is a metric for measuring the difference between two strings.

@docs distance

-}

-- Copied from dasch/levenshtein v1.0.3

import Array exposing (Array)
import Elm.Review.Vendor.Table as Table exposing (Table)


{-| Computes the Levenshtein distance between two strings.
-}
distance : String -> String -> Int
distance str1 str2 =
    if str1 == str2 then
        0

    else
        distanceHelper
            (Array.fromList (String.toList str1))
            (Array.fromList (String.toList str2))


distanceHelper : Array Char -> Array Char -> Int
distanceHelper arr1 arr2 =
    let
        calculateEditDistanceForChars : Table -> ( Int, Int ) -> ( Table, Int )
        calculateEditDistanceForChars table ( i, j ) =
            case ( Array.get (i - 1) arr1, Array.get (j - 1) arr2 ) of
                ( Just chr1, Just chr2 ) ->
                    let
                        ( table1, dist1 ) =
                            Table.fetch ( i - 1, j ) calculateEditDistanceForChars table

                        ( table2, dist2 ) =
                            Table.fetch ( i, j - 1 ) calculateEditDistanceForChars table1

                        ( table3, dist3 ) =
                            Table.fetch ( i - 1, j - 1 ) calculateEditDistanceForChars table2
                    in
                    ( table3
                      -- A more optimized version of
                      -- min (min (dist1 + 1) (dist2 + 1)) (dist3 + indicator)
                    , if dist3 < dist1 then
                        if dist3 < dist2 then
                            if chr1 /= chr2 then
                                dist3 + 1

                            else
                                dist3

                        else
                            dist2 + 1

                      else if dist1 > dist2 then
                        dist2 + 1

                      else
                        dist1 + 1
                    )

                _ ->
                    ( table, max i j )

        indecesForLastChars =
            ( Array.length arr1, Array.length arr2 )
    in
    calculateEditDistanceForChars (Table.empty indecesForLastChars) indecesForLastChars
        |> Tuple.second

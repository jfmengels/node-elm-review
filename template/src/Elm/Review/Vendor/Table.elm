module Elm.Review.Vendor.Table exposing (Table, empty, fetch)

import Array exposing (Array)



{-
   The algorithm goes across the various combinations of characters in the two strings to be compared.
   The result of every combination can be looked at like a grid:

        -     K     I     T     T     E     N
    - (0,0) (1,0) (2,0) (3,0) (4,0) (5,0) (6,0)
    S (0,1) (1,1) (2,1) (3,1) (4,1) (5,1) (6,1)
    I (0,2) (1,2) (2,2) (3,2) (4,2) (5,2) (6,2)
    T (0,3) (1,3) (2,3) (3,3) (4,3) (5,3) (6,3)
    T (0,4) (1,4) (2,4) (3,4) (4,4) (5,4) (6,4)
    I (0,5) (1,5) (2,5) (3,5) (4,5) (5,5) (6,5)
    N (0,6) (1,6) (2,6) (3,6) (4,6) (5,6) (6,6)
    G (0,7) (1,7) (2,7) (3,7) (4,7) (5,7) (6,7)

   Note that each row and column have room for one more element than the length of the string they represent.
   To store the result for each comparison efficiently, we use a flat array, where the data looks like this:

    [ (0,0), (1,0), (2,0), (3,0), (4,0), (5,0), (6,0), (0,1), (1,1), (2,1), (3,1), etc.]

   Where the index to read from can be calculated from the key and the "width" of the grid.
-}


type Table
    = Table Int (Array Int)


empty : ( Int, Int ) -> Table
empty ( sizeA, sizeB ) =
    let
        arraySize =
            (sizeA + 1) * (sizeB + 1) - 1
    in
    Table (sizeB + 1) (Array.repeat arraySize -1)


fetch : ( Int, Int ) -> (Table -> ( Int, Int ) -> ( Table, Int )) -> Table -> ( Table, Int )
fetch (( iKey, jKey ) as key) builder ((Table dimension store) as table) =
    let
        index =
            iKey * dimension + jKey
    in
    case Array.get index store of
        Just value ->
            if value == -1 then
                let
                    ( Table _ newStore, newValue ) =
                        builder table key
                in
                ( Table dimension (Array.set index newValue newStore), newValue )

            else
                ( table, value )

        Nothing ->
            -- Would only occur if we are out of bounds on the array. This should never happen
            ( table, -1 )

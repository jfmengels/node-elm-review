module Elm.Review.Vendor.Memo exposing (Memo, empty, fetch)

import Dict exposing (Dict)


type alias Memo comparable =
    Dict comparable Int


empty : Memo comparable
empty =
    Dict.empty


fetch : comparable -> (Memo comparable -> comparable -> ( Memo comparable, Int )) -> Memo comparable -> ( Memo comparable, Int )
fetch key f memo =
    case Dict.get key memo of
        Just value ->
            ( memo, value )

        Nothing ->
            let
                ( newMemo, value ) =
                    f memo key
            in
            ( Dict.insert key value newMemo, value )

module Elm.Review.UnsuppressMode exposing (UnsuppressMode(..), decoder)

import Json.Decode as Decode
import Set exposing (Set)


type UnsuppressMode
    = UnsuppressAll
    | UnsuppressRules (Set String)
    | UnsuppressNone


decoder : Decode.Decoder UnsuppressMode
decoder =
    Decode.oneOf
        [ Decode.list Decode.string
            |> Decode.map (Set.fromList >> UnsuppressRules)
        , Decode.bool
            |> Decode.map
                (\bool ->
                    if bool then
                        UnsuppressAll

                    else
                        UnsuppressNone
                )
        ]

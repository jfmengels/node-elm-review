module Wrapper.Prompt exposing (interpretKey, KeyInterpretation(..))

{-|

@docs interpretKey, KeyInterpretation

-}

import Stdin exposing (Key(..))


type KeyInterpretation
    = Yes
    | No
    | Unknown


interpretKey : Key -> KeyInterpretation
interpretKey key =
    case key of
        KeyChar char ->
            interpretCharKey char

        KeyEnter ->
            Yes

        KeyEscape ->
            No

        _ ->
            Unknown


interpretCharKey : Char -> KeyInterpretation
interpretCharKey char =
    case char of
        'y' ->
            Yes

        'Y' ->
            Yes

        'n' ->
            No

        'N' ->
            No

        _ ->
            Unknown

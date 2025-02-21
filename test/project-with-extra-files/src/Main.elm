module Main exposing (main)

import Browser
import Html exposing (Html, div, text)
import Html.Attributes


type alias Model =
    { count : Int }


initialModel : Model
initialModel =
    { count = 0 }


view : Model -> Html msg
view _ =
    div
        [ Html.Attributes.class "from-css-1"
        , Html.Attributes.class "from-css-2"
        , Html.Attributes.class "from-css-3"
        , Html.Attributes.class "unknown-css"
        ]
        [ text "+1"
        ]


main : Program () Model msg
main =
    Browser.sandbox
        { init = initialModel
        , view = view
        , update = \_ model -> model
        }

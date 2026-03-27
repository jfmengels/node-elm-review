module Wrapper.Help exposing (show)

import Wrapper.Color as Color
import Wrapper.Subcommand exposing (Subcommand)


show : Color.Support -> Maybe Subcommand -> String
show colorSupport maybeSubcommand =
    case maybeSubcommand of
        Nothing ->
            "This is the help!"

        Just section ->
            "This is the help for a section"

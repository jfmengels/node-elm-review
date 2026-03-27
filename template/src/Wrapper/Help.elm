module Wrapper.Help exposing (show)

import Wrapper.Color as Color
import Wrapper.Subcommand as Subcommand exposing (Subcommand)


show : Color.Support -> Maybe Subcommand -> String
show colorSupport maybeSubcommand =
    case maybeSubcommand of
        Nothing ->
            "This is the help!"

        Just Subcommand.Init ->
            "This is the help for init."

        Just _ ->
            "This is the help for a section"

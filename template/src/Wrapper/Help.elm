module Wrapper.Help exposing (show)

import Wrapper.Color exposing (Colorize)
import Wrapper.Subcommand as Subcommand exposing (Subcommand)


show : Colorize -> Maybe Subcommand -> String
show c maybeSubcommand =
    case maybeSubcommand of
        Nothing ->
            "This is the help!"

        Just Subcommand.Init ->
            "This is the help for init."

        Just _ ->
            "This is the help for a section"

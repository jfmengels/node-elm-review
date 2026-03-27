module Wrapper.Anonymize exposing (version)

{-| This module aims to make the paths and versions used in the CLI generic,
so that the CLI tests (in the `test/` folder) have the same output on different
machines, and also the same output when only the CLI version changes.

@docs version

-}

import Elm.Review.CliVersion as CliVersion


{-| Get the version to print to the user
-}
version : { options | forTests : Bool } -> String
version { forTests } =
    if forTests then
        "<version>"

    else
        CliVersion.version

module Elm.Review.CliVersion exposing (anonymizedVersion, version)

{-| TODO Keep in sync with package.json
-}


version : String
version =
    "2.13.5"


{-| Get the version to print to the user?
-}
anonymizedVersion : { options | forTests : Bool } -> String
anonymizedVersion { forTests } =
    if forTests then
        "<version>"

    else
        version

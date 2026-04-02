module Wrapper.MinVersion exposing (validate)

import Elm.Version
import ElmReview.Color exposing (Color(..), Colorize)
import ElmReview.Problem exposing (ProblemSimple)
import Wrapper.Options as Options exposing (ReviewOptions, ReviewProject)
import Wrapper.PathHelpers as PathHelpers


minimalVersion : { major : Int, minor : Int }
minimalVersion =
    { major = 2, minor = 15 }


nextMajor : Int
nextMajor =
    minimalVersion.major + 1


supportedRange : String
supportedRange =
    String.fromInt minimalVersion.major ++ "." ++ String.fromInt minimalVersion.minor ++ ".0 <= v < " ++ String.fromInt nextMajor ++ ".0.0"


{-| Validates that the `jfmengels/elm-review` version is compatible with this runner.
-}
validate : ReviewProject -> String -> Elm.Version.Version -> Maybe ProblemSimple
validate reviewProject reviewFolder version =
    let
        ( major, minor, _ ) =
            Elm.Version.toTuple version
    in
    if major == minimalVersion.major && minor >= minimalVersion.minor then
        Nothing

    else
        Just
            { title = "UNSUPPORTED ELM-REVIEW VERSION"
            , message =
                case reviewProject of
                    Options.Local _ ->
                        localErrorMessage reviewFolder version

                    Options.Remote _ ->
                        \c -> "The template uses an unsupported version of the " ++ c GreenBright "jfmengels/elm-review" ++ " Elm package. It is using version " ++ Elm.Version.toString version ++ ", but I need it to be " ++ supportedRange ++ """.

Please inform the template author and kindly ask them to update their configuration, or make a pull request to help them out."""
            }


localErrorMessage : String -> Elm.Version.Version -> Colorize -> String
localErrorMessage reviewFolder version c =
    let
        dirPath : String
        dirPath =
            PathHelpers.format reviewFolder
    in
    "You are using an unsupported version of the " ++ c GreenBright "jfmengels/elm-review" ++ """ Elm package.
You are using version """ ++ c Red (Elm.Version.toString version) ++ ", but I need it to be " ++ c GreenBright supportedRange ++ """.

Please upgrade your version by running the following commands:

""" ++ c Magenta ("cd " ++ dirPath ++ "\nnpx elm-json install jfmengels/elm-review@" ++ String.fromInt minimalVersion.major) ++ """

If that doesn't work, try out:

""" ++ c Magenta ("cd " ++ dirPath ++ "\nnpx elm-json upgrade --unsafe")

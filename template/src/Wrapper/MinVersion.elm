module Wrapper.MinVersion exposing
    ( validate, validateDependencyVersion
    , supportedRange
    )

{-|

@docs validate, validateDependencyVersion
@docs supportedRange

-}

import Elm.Package
import Elm.Project
import Elm.Version
import ElmReview.Color exposing (Color(..), Colorize)
import ElmReview.Path as Path
import ElmReview.Problem exposing (ProblemSimple)
import Wrapper.Options as Options exposing (ReviewProject)
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
validate : ReviewProject -> Elm.Version.Version -> Maybe ProblemSimple
validate reviewProject version =
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
                    Options.Local reviewFolder ->
                        localErrorMessage reviewFolder version

                    Options.Remote _ ->
                        \c -> "The template uses an unsupported version of the " ++ c GreenBright "jfmengels/elm-review" ++ " Elm package. It is using version " ++ Elm.Version.toString version ++ ", but I need it to be " ++ supportedRange ++ """.

Please inform the template author and kindly ask them to update their configuration, or make a pull request to help them out."""
            }


validateDependencyVersion : ReviewProject -> Elm.Project.ApplicationInfo -> Maybe ProblemSimple
validateDependencyVersion reviewProject application =
    case find (\( name, _ ) -> Elm.Package.toString name == "jfmengels/elm-review") application.depsDirect of
        Just ( _, version ) ->
            validate reviewProject version

        Nothing ->
            Just
                { title = "MISSING ELM-REVIEW DEPENDENCY"
                , message =
                    case reviewProject of
                        Options.Local reviewFolder ->
                            \c ->
                                c Yellow (Path.join2 reviewFolder "elm.json") ++ " does not include " ++ c GreenBright "jfmengels/elm-review" ++ """ in its direct dependencies.

Please add it by running """ ++ c Magenta "elm install jfmengels/elm-review" ++ " inside of " ++ c Yellow reviewFolder ++ "."

                        Options.Remote _ ->
                            \c ->
                                "The template's configuration does not include " ++ c GreenBright "jfmengels/elm-review" ++ """ in its direct dependencies.

Maybe you chose the wrong template, or the template is malformed. If the latter is the case, please inform the template author."""
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


{-| Find the first element that satisfies a predicate and return
Just that element. If none match, return Nothing.
find (\\num -> num > 5) [2, 4, 6, 8] == Just 6
-}
find : (a -> Bool) -> List a -> Maybe a
find predicate list =
    case list of
        [] ->
            Nothing

        first :: rest ->
            if predicate first then
                Just first

            else
                find predicate rest

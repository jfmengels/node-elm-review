module Wrapper.Build exposing
    ( build
    , Msg, update
    )

{-|

@docs build

@docs Msg, update

-}

import Elm.Package
import Elm.Project
import Fs exposing (FileSystem, FsError)
import Json.Decode as Decode
import Task exposing (Task)
import Wrapper.Color exposing (Color(..), Colorize)
import Wrapper.Hash as Hash
import Wrapper.MinVersion as MinVersion
import Wrapper.Options as Options exposing (Options, ReviewProject)
import Wrapper.Path exposing (Path)
import Wrapper.Problem as Problem exposing (Problem, ProblemSimple)


type Msg
    = ReceivedReviewElmJson (Result Problem Elm.Project.ApplicationInfo)


update : Msg -> Result Problem ()
update msg =
    case msg of
        ReceivedReviewElmJson result ->
            Result.map (\_ -> ()) result


build : FileSystem -> Options -> Cmd Msg
build fs options =
    case options.reviewProject of
        Options.Local reviewFolder ->
            buildLocalProject fs options reviewFolder

        Options.Remote remoteTemplate ->
            Debug.todo "Build remote template"


buildLocalProject : FileSystem -> Options -> String -> Cmd Msg
buildLocalProject fs options reviewFolder =
    let
        pathToElmJson : String
        pathToElmJson =
            -- TODO Use path functions
            String.join "/" [ reviewFolder, "elm.json" ]
    in
    readReviewElmJson fs options.reviewProject reviewFolder pathToElmJson
        |> Task.andThen
            (\{ raw, application } ->
                cachedBuild options reviewFolder pathToElmJson application.dirs
                    |> Task.map (\appHash -> application)
            )
        |> Task.attempt ReceivedReviewElmJson


readReviewElmJson : FileSystem -> ReviewProject -> String -> String -> Task Problem { raw : String, application : Elm.Project.ApplicationInfo }
readReviewElmJson fs reviewProject reviewFolder pathToElmJson =
    fetchElmJson fs reviewFolder pathToElmJson
        |> Task.andThen
            (\rawElmJson ->
                parseElmJson reviewProject reviewFolder pathToElmJson rawElmJson
                    |> Result.mapError (Problem.from >> Problem.withPath pathToElmJson)
                    |> resultToTask
            )


fetchElmJson : FileSystem -> String -> String -> Task Problem String
fetchElmJson fs reviewFolder pathToElmJson =
    Fs.readTextFile fs pathToElmJson
        |> Task.mapError
            (\error ->
                case error of
                    Fs.NotFound _ ->
                        { title = "INCORRECT CONFIGURATION"
                        , message =
                            \c ->
                                "I could not find a review configuration. I was expecting to find an " ++ c Yellow "elm.json" ++ " file and a " ++ c Cyan "ReviewConfig.elm" ++ " file in " ++ c Cyan (reviewFolder ++ "/") ++ """.

I can help set you up with an initial configuration if you run """ ++ c Magenta "elm-review init" ++ "."
                        }
                            |> Problem.from
                            |> Problem.withPath pathToElmJson

                    Fs.PermissionDenied ->
                        { title = "PERMISSION DENIED"
                        , message =
                            \c ->
                                "I tried reading " ++ c Yellow pathToElmJson ++ """ but couldn't because of the file's read permissions.

Try changing the permissions of the file and/or its parents directories."""
                        }
                            |> Problem.from
                            |> Problem.withPath pathToElmJson

                    Fs.IoError string ->
                        Debug.todo ("Unknown error: " ++ string)
            )


parseElmJson : ReviewProject -> String -> String -> String -> Result ProblemSimple { raw : String, application : Elm.Project.ApplicationInfo }
parseElmJson reviewProject reviewFolder pathToElmJson rawElmJson =
    case Decode.decodeString Elm.Project.decoder rawElmJson of
        Err error ->
            Err
                { title = "COULD NOT READ ELM.JSON"
                , message = decodingErrorMessage pathToElmJson error
                }

        Ok (Elm.Project.Package _) ->
            Err
                { title = "REVIEW CONFIG IS NOT AN APPLICATION"
                , message =
                    \c ->
                        "I wanted to use " ++ c Yellow pathToElmJson ++ " as the basis for the configuration, and I expected it to be an " ++ c Yellow "application" ++ """, but it wasn't.

I think it is likely that you are pointing to an incorrect configuration file. Please check the path to your configuration again."""
                }

        Ok (Elm.Project.Application application) ->
            case validateElmReviewVersion reviewProject reviewFolder application of
                Just problem ->
                    Err problem

                Nothing ->
                    Ok { raw = rawElmJson, application = application }


validateElmReviewVersion : ReviewProject -> String -> Elm.Project.ApplicationInfo -> Maybe ProblemSimple
validateElmReviewVersion reviewProject reviewFolder application =
    case find (\( name, _ ) -> Elm.Package.toString name == "jfmengels/elm-review") application.depsDirect of
        Just ( _, version ) ->
            MinVersion.validate reviewProject reviewFolder version

        Nothing ->
            Just
                { title = "MISSING ELM-REVIEW DEPENDENCY"
                , message =
                    \c ->
                        "The template's configuration does not include " ++ c GreenBright "jfmengels/elm-review" ++ """ in its direct dependencies.

Maybe you chose the wrong template, or the template is malformed. If the latter is the case, please inform the template author."""
                }


{-| Get the hash associated to the current review application.
This is either retrieved from a cache or computed.
-}
cachedBuild : Options -> Path -> Path -> List Path -> Task x Hash.Hash
cachedBuild options userSrc reviewElmJsonPath sourceDirectories =
    Task.succeed (Hash.fromString "some-hash")


decodingErrorMessage : String -> Decode.Error -> Colorize -> String
decodingErrorMessage pathToElmJson error c =
    "I tried reading " ++ c Yellow pathToElmJson ++ """ but encountered an error while reading it. Please check that it is valid JSON that the Elm compiler would be happy with.

Here is the error I encountered:

""" ++ Decode.errorToString error


resultToTask : Result x a -> Task x a
resultToTask result =
    case result of
        Ok value ->
            Task.succeed value

        Err err ->
            Task.fail err


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

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
import Wrapper.Options as Options exposing (Options)
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
    readReviewElmJson fs reviewFolder
        |> Task.attempt ReceivedReviewElmJson


readReviewElmJson : FileSystem -> String -> Task Problem Elm.Project.ApplicationInfo
readReviewElmJson fs reviewFolder =
    let
        pathToElmJson : String
        pathToElmJson =
            -- TODO Use path functions
            String.join "/" [ reviewFolder, "elm.json" ]
    in
    fetchElmJson fs reviewFolder pathToElmJson
        |> Task.andThen
            (\rawElmJson ->
                parseElmJson pathToElmJson rawElmJson
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


parseElmJson : String -> String -> Result ProblemSimple Elm.Project.ApplicationInfo
parseElmJson pathToElmJson rawElmJson =
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
            validateElmReviewVersion application


validateElmReviewVersion : Elm.Project.ApplicationInfo -> Result ProblemSimple Elm.Project.ApplicationInfo
validateElmReviewVersion application =
    case find (\( name, _ ) -> Elm.Package.toString name == "jfmengels/elm-review") application.depsDirect of
        Just version ->
            Ok application

        Nothing ->
            Err
                { title = "MISSING ELM-REVIEW DEPENDENCY"
                , message =
                    \c ->
                        "The template's configuration does not include " ++ c GreenBright "jfmengels/elm-review" ++ """ in its direct dependencies.

Maybe you chose the wrong template, or the template is malformed. If the latter is the case, please inform the template author."""
                }


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

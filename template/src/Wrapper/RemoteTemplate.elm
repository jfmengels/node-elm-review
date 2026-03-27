module Wrapper.RemoteTemplate exposing (RemoteTemplate, fromString)

import Regex exposing (Regex)


type alias RemoteTemplate =
    { repoName : String
    , pathToFolder : Maybe String
    , reference : Maybe String
    }


fromString : String -> Result () RemoteTemplate
fromString string =
    let
        regex : Regex
        regex =
            "^([^/]+\\/[^#/]+)(\\/[^#]+)?(#(.+))?$"
                |> Regex.fromString
                |> Maybe.withDefault Regex.never
    in
    case Regex.findAtMost 1 regex string |> List.map .submatches of
        [ Just repoName, pathToFolder, _, reference ] :: _ ->
            Ok
                { repoName = repoName
                , pathToFolder = pathToFolder
                , reference = reference
                }

        _ ->
            Err ()

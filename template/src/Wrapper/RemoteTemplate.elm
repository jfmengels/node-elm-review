module Wrapper.RemoteTemplate exposing (RemoteTemplate, fromString)

import ElmReview.Path as Path


type alias RemoteTemplate =
    { repoName : String
    , pathToFolder : Maybe String
    , reference : Maybe String
    }


fromString : String -> Result () RemoteTemplate
fromString string =
    case String.split "#" string of
        [] ->
            Err ()

        repoNameAndPath :: rest ->
            case String.split "/" repoNameAndPath of
                pkgAuthor :: pkgName :: pathToFolder ->
                    let
                        ref : Result () (Maybe String)
                        ref =
                            case rest of
                                [] ->
                                    Ok Nothing

                                [ reference ] ->
                                    Ok (Just reference)

                                _ ->
                                    Err ()
                    in
                    Result.map
                        (\reference ->
                            { repoName = pkgAuthor ++ "/" ++ pkgName
                            , pathToFolder =
                                if List.isEmpty pathToFolder then
                                    Nothing

                                else
                                    Just (Path.join pathToFolder)
                            , reference = reference
                            }
                        )
                        ref

                _ ->
                    Err ()

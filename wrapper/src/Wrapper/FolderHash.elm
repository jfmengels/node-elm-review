module Wrapper.FolderHash exposing (hashSourceDirectories)

import ElmReview.Path as Path exposing (Path)
import ElmRun.TaskExtra as TaskExtra
import Fs exposing (FileSystem)
import Task exposing (Task)
import Wrapper.Hash as Hash exposing (Hash)


hashSourceDirectories : FileSystem -> Path -> List Path -> Task x Hash
hashSourceDirectories fs reviewFolder sourceDirectories =
    sourceDirectories
        |> List.map
            (\directory ->
                let
                    dirPath : Path
                    dirPath =
                        Path.join2 reviewFolder directory
                in
                Fs.walkTree fs dirPath (Just "*.elm") Fs.Any
                    |> Task.andThen (\( files, _ ) -> readFiles fs dirPath files)
                    |> Task.onError (\_ -> Task.succeed [])
            )
        |> Task.sequence
        |> Task.map hashFiles


readFiles : FileSystem -> Path -> List Path -> Task x (List ( Path, String ))
readFiles fs dirPath files =
    TaskExtra.mapAllAndFold
        (\file ->
            let
                path : Path
                path =
                    Path.join2 dirPath file
            in
            Fs.readTextFile fs path
                |> Task.map (\content -> Just ( file, content ))
                |> Task.onError (\_ -> Task.succeed Nothing)
        )
        maybeCons
        []
        files


maybeCons : Maybe a -> List a -> List a
maybeCons maybe list =
    case maybe of
        Just a ->
            a :: list

        Nothing ->
            list


hashFiles : List (List ( comparable, String )) -> Hash
hashFiles files =
    files
        |> List.concat
        |> List.sortBy Tuple.first
        |> Hash.fromList Tuple.second Hash.initial

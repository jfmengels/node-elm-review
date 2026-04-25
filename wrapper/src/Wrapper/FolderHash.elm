module Wrapper.FolderHash exposing (hashApplication)

import Elm.Package
import Elm.Project
import Elm.Version
import ElmReview.Path as Path exposing (Path)
import ElmRun.TaskExtra as TaskExtra
import Fs exposing (FileSystem)
import Task exposing (Task)
import Wrapper.Hash as Hash exposing (Hash)


hashApplication : FileSystem -> Path -> Maybe Path -> Elm.Project.ApplicationInfo -> Task x Hash
hashApplication fs reviewFolder localElmReview application =
    let
        sourceDirectories : List Path
        sourceDirectories =
            case localElmReview of
                Just localElmReview_ ->
                    Path.join2 localElmReview_ "src" :: application.dirs

                Nothing ->
                    application.dirs

        elmJsonHash : Hash
        elmJsonHash =
            (application.depsDirect
                ++ application.depsIndirect
                ++ application.testDepsDirect
                ++ application.testDepsIndirect
            )
                |> List.map (\( pkgName, version ) -> ( Elm.Package.toString pkgName, Elm.Version.toString version ))
                |> hashList (\( pkgName, version ) -> pkgName ++ ":" ++ version ++ ";") Hash.initial
    in
    TaskExtra.mapAllAndFold
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
        (++)
        []
        sourceDirectories
        |> Task.map (\files -> hashList Tuple.second elmJsonHash files)


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


hashList : (( comparable, a ) -> String) -> Hash -> List ( comparable, a ) -> Hash
hashList toString initialHash list =
    list
        |> List.sortBy Tuple.first
        |> Hash.fromList toString initialHash

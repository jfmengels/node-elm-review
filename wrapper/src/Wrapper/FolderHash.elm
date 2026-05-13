module Wrapper.FolderHash exposing (hashApplication)

import Elm.Package
import Elm.Project
import Elm.Review.Testable.Fs as Fs
import Elm.Review.Testable.FsData as FsData
import Elm.Review.Testable.TTask as TTask exposing (TTask)
import Elm.Version
import ElmReview.Path as Path exposing (Path)
import Wrapper.Hash as Hash exposing (Hash)


hashApplication : Path -> Maybe Path -> Elm.Project.ApplicationInfo -> TTask x Hash
hashApplication reviewFolder localElmReview application =
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
    TTask.mapAllAndFold
        (\directory ->
            let
                dirPath : Path
                dirPath =
                    Path.join2 reviewFolder directory
            in
            Fs.walkTree dirPath (Just "*.elm") FsData.Any
                |> TTask.andThen (\files -> readFiles dirPath files)
                |> TTask.onError (\_ -> TTask.succeed [])
        )
        (++)
        []
        sourceDirectories
        |> TTask.map (\files -> hashList Tuple.second elmJsonHash files)


readFiles : Path -> List Path -> TTask x (List ( Path, String ))
readFiles dirPath files =
    TTask.mapAllAndFold
        (\file ->
            let
                path : Path
                path =
                    Path.join2 dirPath file
            in
            Fs.readTextFile path
                |> TTask.map (\content -> Just ( file, content ))
                |> TTask.onError (\_ -> TTask.succeed Nothing)
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

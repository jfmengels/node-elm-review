module Elm.Review.Testable.Fs exposing
    ( copyDirectory
    , createDirectory
    , createFileAndItsDirectory
    , createSymlink
    , deleteFile
    , list
    , readTextFile
    , removeDirectory
    , stat
    , walkTree
    , writeBytes
    , writeTextFile
    )

import Bytes exposing (Bytes)
import Elm.Review.Testable.FsData exposing (Entry, FileStat, FsError, MatchKind)
import Elm.Review.Testable.Internal as Internal
import Elm.Review.Testable.TTask as TTask exposing (TTask)
import ElmReview.Path as Path exposing (Path)


{-| Get file or directory metadata without following symlinks.
-}
stat : Path -> TTask FsError FileStat
stat path =
    Internal.Stat path Internal.resultFromResult


{-| List the direct children of a directory.

Returns `Entry` records with full metadata (no separate `stat` needed).
Equivalent to a walk with `maxDepth = 0`.

    Fs.list fs (Fs.Location.dir "src")

-}
list : Path -> TTask FsError (List Entry)
list path =
    Internal.List path Internal.resultFromResult


{-| Read a file as a String.
-}
readTextFile : Path -> TTask FsError String
readTextFile path =
    Internal.ReadTextFile path Internal.resultFromResult


{-| Write a String to a file.
-}
writeTextFile : Path -> String -> TTask FsError ()
writeTextFile path string =
    Internal.WriteTextFile path string Internal.resultFromResult


{-| Write binary data (Bytes) to a file.
-}
writeBytes : Path -> Bytes -> TTask FsError ()
writeBytes path bytes =
    Internal.WriteBytes path bytes Internal.resultFromResult


createFileAndItsDirectory : Path -> String -> TTask FsError ()
createFileAndItsDirectory path content =
    createDirectory (Path.dirname path)
        |> TTask.andThen (\() -> writeTextFile path content)


{-| Delete a file. Succeeds silently if the file does not exist.
-}
deleteFile : Path -> TTask FsError ()
deleteFile path =
    Internal.DeleteFile path Internal.resultFromResult


{-| Create a directory and all parent directories (like mkdir -p).
Succeeds silently if the directory already exists.
-}
createSymlink : { target : Path, linkPath : Path } -> TTask FsError ()
createSymlink targets =
    Internal.CreateSymlink targets Internal.resultFromResult


{-| Create a directory and all parent directories (like mkdir -p).
Succeeds silently if the directory already exists.
-}
createDirectory : Path -> TTask FsError ()
createDirectory path =
    Internal.CreateDirectory path Internal.resultFromResult


{-| Recursively remove a directory and all its contents.
Succeeds silently if the directory does not exist.
-}
removeDirectory : Path -> TTask FsError ()
removeDirectory path =
    Internal.RemoveDirectory path Internal.resultFromResult


copyDirectory : { from : Path, to : Path } -> TTask FsError ()
copyDirectory targets =
    Internal.CopyDirectory targets Internal.resultFromResult


{-| Walk a directory tree and return matched paths.

The second argument is an optional glob pattern to filter names, and the
third argument limits which kinds of entries are considered via
`MatchKind`.

-}
walkTree : Path -> Maybe String -> MatchKind -> TTask FsError (List Path)
walkTree path pattern matchKind =
    Internal.WalkTree path pattern matchKind Internal.resultFromResult

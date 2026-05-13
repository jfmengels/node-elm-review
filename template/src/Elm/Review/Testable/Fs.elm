module Elm.Review.Testable.Fs exposing
    ( copyDirectory
    , createDirectory
    , deleteFile
    , readTextFile
    , removeDirectory
    , stat
    , walkTree
    , writeTextFile
    )

import Elm.Review.Testable.FsData exposing (FileStat, FsError, MatchKind)
import Elm.Review.Testable.Internal as Internal
import Elm.Review.Testable.ProcessData exposing (ProcessError, SpawnError)
import Elm.Review.Testable.TTask exposing (TTask)
import ElmReview.Path exposing (Path)


{-| Get file or directory metadata without following symlinks.
-}
stat : Path -> TTask FsError FileStat
stat path =
    Internal.Stat path Internal.resultFromResult


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


{-| Delete a file. Succeeds silently if the file does not exist.
-}
deleteFile : Path -> TTask FsError ()
deleteFile path =
    Internal.DeleteFile path Internal.resultFromResult


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


copyDirectory : { from : Path, to : Path } -> TTask SpawnError ()
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

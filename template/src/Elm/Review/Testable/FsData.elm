module Elm.Review.Testable.FsData exposing
    ( FileStat
    , FsError(..)
    , MatchKind(..)
    , errorToString
    )


type FsError
    = PermissionDenied
    | NotFound String
    | IoError String


{-| The kind of file system entry to match during the tree traversal.
-}
type MatchKind
    = Any
    | File
    | Directory


{-| File metadata returned by stat.
-}
type alias FileStat =
    { isFile : Bool
    , isDirectory : Bool
    , isSymlink : Bool
    , size : Int
    , modifiedTime : Int
    }


errorToString : FsError -> String
errorToString fsError =
    case fsError of
        NotFound path ->
            "File not found: " ++ path

        PermissionDenied ->
            "Permission denied"

        IoError msg ->
            "Unknown error: " ++ msg

module Elm.Review.Testable.Fs exposing
    ( FileStat
    , FsError(..)
    , MatchKind(..)
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


type StdinError
    = PermissionDenied
    | EndOfInput
    | IoError String


{-| A keypress decoded by the native runtime.

This is intentionally small and focused on what a terminal editor needs.

-}
type Key
    = KeyChar Char
    | KeyCtrl Char
    | KeyEnter
    | KeyBackspace
    | KeyDelete
    | KeyEscape
    | KeyArrowUp
    | KeyArrowDown
    | KeyArrowLeft
    | KeyArrowRight
    | KeyHome
    | KeyEnd
    | KeyPageUp
    | KeyPageDown
    | KeyMouseWheelUp
    | KeyMouseWheelDown

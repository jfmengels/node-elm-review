module Elm.Review.Testable.Fs exposing (FsError(..), MatchKind(..))


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

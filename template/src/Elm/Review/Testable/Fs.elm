module Elm.Review.Testable.Fs exposing (FsError(..))


type FsError
    = PermissionDenied
    | NotFound String
    | IoError String

module Elm.Review.Testable.ProcessData exposing (ProcessError(..))


type ProcessError
    = PermissionDenied
    | CaptureLimitExceeded String
    | ProcessError String

module Elm.Review.Testable.StdinData exposing
    ( Key(..)
    , StdinError(..)
    )


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

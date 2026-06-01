module Elm.Review.Prompt exposing
    ( prompt
    , Msg, update
    , PromptResult(..)
    )

{-|

@docs prompt
@docs Msg, update
@docs PromptResult

-}

import Elm.Review.Testable.Cli as Cli
import Elm.Review.Testable.Internal exposing (TCmd)
import Elm.Review.Testable.Stdin as Stdin
import Elm.Review.Testable.StdinData as Stdin exposing (Key(..), StdinError)
import Elm.Review.Testable.TTask as TTask
import ElmReview.Color as Color exposing (Color(..), Colorize)
import ElmReview.Problem as Problem exposing (Problem)


type Msg
    = UserPressedKey (Problem.FormatOptions {}) (Result Problem.Exit Stdin.Key)


prompt : { formatOptions : Problem.FormatOptions {}, priorMessage : Maybe String, question : Colorize -> String } -> TCmd Msg
prompt { formatOptions, priorMessage, question } =
    let
        message : String
        message =
            case priorMessage of
                Just str ->
                    str ++ "\n\n"

                Nothing ->
                    ""

        c : Colorize
        c =
            Color.toAnsi formatOptions.color

        question_ : String
        question_ =
            Color.bold formatOptions.color (question c)
    in
    Cli.printlnStdoutTask (message ++ question_ ++ c Gray " (Y/n)" ++ "")
        |> TTask.andThen (\() -> promptForConfirmation formatOptions)
        |> TTask.attempt (UserPressedKey formatOptions)


type PromptResult
    = Accepted
    | Refused
    | TriggerCmd (TCmd Msg)


update : Msg -> PromptResult
update msg =
    case msg of
        UserPressedKey formatOptions (Ok key) ->
            case interpretKey key of
                Just True ->
                    Accepted

                Just False ->
                    Refused

                Nothing ->
                    promptForConfirmation formatOptions
                        |> TTask.attempt (UserPressedKey formatOptions)
                        |> TriggerCmd

        UserPressedKey _ (Err exit) ->
            Problem.exit exit
                |> TriggerCmd


promptForConfirmation : Problem.FormatOptions {} -> TTask.TTask Problem.Exit Key
promptForConfirmation formatOptions =
    Stdin.readKey
        |> TTask.onError (\error -> Stdin.toProblem "while prompting for confirmation" error |> Problem.exitOnUnrecoverable formatOptions)


interpretKey : Key -> Maybe Bool
interpretKey key =
    case key of
        KeyChar char ->
            interpretCharKey char

        KeyEnter ->
            yes

        KeyEscape ->
            no

        _ ->
            Nothing


interpretCharKey : Char -> Maybe Bool
interpretCharKey char =
    case char of
        'y' ->
            yes

        'Y' ->
            yes

        'n' ->
            no

        'N' ->
            no

        _ ->
            Nothing


yes : Maybe Bool
yes =
    Just True


no : Maybe Bool
no =
    Just False

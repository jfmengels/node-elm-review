module ElmRun.Prompt exposing
    ( prompt
    , Msg, update
    , PromptResult(..)
    )

{-|

@docs prompt
@docs Msg, update

-}

import Capabilities exposing (Console, Stdin)
import Cli
import ElmReview.Color as Color exposing (Color(..), Colorize)
import Stdin exposing (Key(..), StdinError)
import Task


type Msg
    = UserPressedKey Stdin (Result StdinError Stdin.Key)


prompt : Stdin -> Console -> { color : Color.Support, priorMessage : Maybe String, question : Colorize -> String } -> Cmd Msg
prompt stdin stdout { color, priorMessage, question } =
    let
        message : String
        message =
            case priorMessage of
                Just str ->
                    str ++ "\n\n"

                Nothing ->
                    ""

        question_ : String
        question_ =
            Color.bold color (question (Color.toAnsi color))

        yesNo : String
        yesNo =
            Color.toAnsi color Gray " (Y/n)"
    in
    Cmd.batch
        [ Cli.println stdout (message ++ question_ ++ yesNo ++ "")
        , Stdin.readKey stdin
            |> Task.attempt (UserPressedKey stdin)
        ]


type PromptResult
    = Accepted
    | Refused
    | TriggerCmd (Cmd Msg)


update : Msg -> PromptResult
update msg =
    case msg of
        -- TODO Figure out how to get interactive keypresses that don't wait for the Enter key
        UserPressedKey stdin (Ok key) ->
            case interpretKey key of
                Just True ->
                    Accepted

                Just False ->
                    Refused

                Nothing ->
                    Stdin.readKey stdin
                        |> Task.attempt (UserPressedKey stdin)
                        |> TriggerCmd

        UserPressedKey _ (Err err) ->
            Debug.todo ("Got error while awaiting key: " ++ Debug.toString err)


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

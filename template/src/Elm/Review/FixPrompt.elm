module Elm.Review.FixPrompt exposing
    ( Model, init
    , Msg, update
    , prompt
    , PromptResult(..)
    )

{-|

@docs Model, init
@docs Msg, update
@docs prompt

-}

import Capabilities exposing (Console, Stdin)
import ElmRun.Prompt as Prompt


type Model
    = Model ModelData


type alias ModelData =
    { promptId : Int
    }


init : Model
init =
    Model
        { promptId = 0
        }


type Msg payload
    = PromptMsg Int payload Prompt.Msg


prompt : Stdin -> Console -> Model -> payload -> String -> ( Model, Cmd (Msg payload) )
prompt stdin stdout (Model model) payload promptText =
    let
        promptId : Int
        promptId =
            model.promptId + 1
    in
    ( Model { model | promptId = promptId }
    , Prompt.prompt stdin stdout promptText
        |> Cmd.map (PromptMsg promptId payload)
    )


type PromptResult payload
    = Accepted payload
    | Refused
    | TriggerCmd (Cmd (Msg payload))
    | Ignore


update : Msg payload -> Model -> PromptResult payload
update (PromptMsg msgPromptId payload promptMsg) (Model { promptId }) =
    if msgPromptId == promptId then
        case Prompt.update promptMsg of
            Prompt.Accepted ->
                Accepted payload

            Prompt.Refused ->
                Refused

            Prompt.TriggerCmd cmd ->
                TriggerCmd (Cmd.map (PromptMsg promptId payload) cmd)

    else
        Ignore

module Elm.Review.InitError exposing
    ( InitError(..)
    , map
    )

import ElmReview.Problem as Problem exposing (Problem)


type InitError a
    = Success a
    | Problem (Problem.FormatOptions {}) Problem
    | StringProblem String


map : (a -> b) -> InitError a -> InitError b
map fn initError =
    case initError of
        Success a ->
            Success (fn a)

        Problem formatOptions problem ->
            Problem formatOptions problem

        StringProblem string ->
            StringProblem string

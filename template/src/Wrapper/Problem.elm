module Wrapper.Problem exposing (FormatOptions, Problem, ProblemSimple, format, from, unexpectedError, unwrapFOR_TESTS, withPath)

import Elm.Review.ReportMode as ReportMode exposing (ReportMode)
import Json.Encode as Encode
import Wrapper.Color as Color exposing (Color(..), Colorize)
import Wrapper.Path exposing (Path)


type Problem
    = Problem
        { title : String
        , message : Colorize -> String
        , path : Maybe Path
        }


type alias ProblemSimple =
    { title : String
    , message : Colorize -> String
    }


from : ProblemSimple -> Problem
from { title, message } =
    Problem
        { title = title
        , message = message
        , path = Nothing
        }


withPath : Path -> Problem -> Problem
withPath path (Problem problem) =
    Problem
        { title = problem.title
        , message = problem.message
        , path = Just path
        }


unwrapFOR_TESTS : Problem -> ProblemSimple
unwrapFOR_TESTS (Problem problem) =
    { title = problem.title
    , message = problem.message
    }


type alias FormatOptions a =
    { a
        | color : Color.Support
        , report : ReportMode
        , debug : Bool
    }


format : FormatOptions a -> Problem -> String
format { color, report, debug } problem =
    let
        c : Colorize
        c =
            Color.toAnsi color
    in
    case report of
        ReportMode.HumanReadable ->
            formatHuman c problem

        ReportMode.Json ->
            formatJson c problem debug

        ReportMode.NDJson ->
            formatJson c problem debug


formatJson : Colorize -> Problem -> Bool -> String
formatJson c problem debug =
    let
        indent : Int
        indent =
            if debug then
                2

            else
                0
    in
    formatJsonHelp c problem
        |> Encode.encode indent


formatHuman : Colorize -> Problem -> String
formatHuman c (Problem { title, message }) =
    c Green ("-- " ++ title ++ " " ++ String.repeat (76 - String.length title) "-") ++ "\n\n" ++ String.trim (message c) ++ "\n"


formatJsonHelp : Colorize -> Problem -> Encode.Value
formatJsonHelp c (Problem { title, message, path }) =
    [ Just ( "type", Encode.string "error" )
    , Just ( "title", Encode.string title )
    , Maybe.map (\p -> ( "path", Encode.string p )) path
    , Just ( "message", Encode.list Encode.string [ String.trim (message c) ] )
    ]
        |> List.filterMap identity
        |> Encode.object


unexpectedError : String -> Problem
unexpectedError message =
    { title = "UNEXPECTED ERROR"
    , message = \c -> """I ran into an unexpected error. Please open an issue at the following link:
  https://github.com/jfmengels/node-elm-review/issues/new

Please include this error message and as much detail as you can provide. Running
with """ ++ c Yellow "--debug" ++ """ might give additional information. If you can, please provide a
setup that makes it easy to reproduce the error. That will make it much easier
to fix the issue.

Below is the error that was encountered.
--------------------------------------------------------------------------------
""" ++ message
    }
        |> from

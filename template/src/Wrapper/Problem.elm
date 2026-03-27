module Wrapper.Problem exposing (FormatOptions, Problem, ProblemSimple, format, from, unwrapFOR_TESTS, withPath)

import Wrapper.Color exposing (Color(..), Colorize)
import Wrapper.ReportMode as ReportMode exposing (ReportMode)


type Problem
    = Problem
        { title : String
        , message : Colorize -> String
        , path : Maybe String
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


withPath : String -> Problem -> Problem
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
        | c : Colorize
        , report : ReportMode
        , debug : Bool
    }


format : FormatOptions a -> Problem -> String
format { c, report, debug } problem =
    case report of
        ReportMode.HumanReadable ->
            formatHuman c problem

        ReportMode.Json ->
            Debug.todo "JSON format"


formatHuman : Colorize -> Problem -> String
formatHuman c (Problem { title, message }) =
    c Green ("--" ++ title ++ String.repeat (76 + String.length title) "-") ++ "\n\n" ++ String.trim (message c)

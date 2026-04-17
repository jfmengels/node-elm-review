module ElmReview.Problem exposing
    ( Problem, from, withPath
    , ProblemSimple
    , invalidElmJson, unexpectedError, notImplementedYet
    , exit
    , FormatOptions
    , unwrapFOR_TESTS
    )

{-|

@docs Problem, from, withPath
@docs ProblemSimple

@docs invalidElmJson, unexpectedError, notImplementedYet

@docs exit

@docs FormatOptions

@docs unwrapFOR_TESTS

-}

import Capabilities exposing (Console)
import Cli
import ElmReview.Color as Color exposing (Color(..), Colorize)
import ElmReview.Path exposing (Path)
import ElmReview.ReportMode as ReportMode exposing (ReportMode)
import Json.Decode as Decode
import Json.Encode as Encode


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


exit : Console -> FormatOptions options -> Problem -> Cmd msg
exit stderr formatOptions problem =
    Cmd.batch
        [ Cli.println stderr (format formatOptions problem)
        , Cli.exit 1
        ]


type alias FormatOptions a =
    { a
        | color : Color.Support
        , reportMode : ReportMode
        , debug : Bool
    }


format : FormatOptions a -> Problem -> String
format { color, reportMode, debug } problem =
    let
        c : Colorize
        c =
            Color.toAnsi color
    in
    case reportMode of
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


invalidElmJson : String -> Decode.Error -> Problem
invalidElmJson pathToElmJson error =
    { title = "COULD NOT READ ELM.JSON"
    , message = decodingErrorMessage pathToElmJson error
    }
        |> from
        |> withPath pathToElmJson


decodingErrorMessage : String -> Decode.Error -> Colorize -> String
decodingErrorMessage pathToElmJson error c =
    "I tried reading " ++ c Yellow pathToElmJson ++ """ but encountered an error while reading it. Please check that it is valid JSON that the Elm compiler would be happy with.

Here is the error I encountered:

""" ++ Decode.errorToString error


unexpectedError : String -> String -> Problem
unexpectedError stepDescription message =
    { title = "UNEXPECTED ERROR"
    , message = \c -> "I ran into an unexpected error " ++ stepDescription ++ """. Please open an issue at the following link:
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


notImplementedYet : String -> Problem
notImplementedYet featureDescription =
    { title = "FEATURE IS NOT IMPLEMENTED YET"
    , message = \_ -> featureDescription ++ " is not implemented yet."
    }
        |> from

module ElmReview.Problem exposing
    ( Problem, from, withPath
    , ProblemSimple
    , invalidElmJson, unexpectedError, notImplementedYet
    , FormatOptions
    , unwrapFOR_TESTS
    , Recovery(..), stop
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
import Wrapper.Options as Options exposing (ReviewProject)
import Wrapper.RemoteTemplate exposing (RemoteTemplate)


type Problem
    = Problem
        { title : String
        , message : Colorize -> String
        , path : Maybe Path
        , recovery : Recovery
        }


type alias ProblemSimple =
    { title : String
    , message : Colorize -> String
    }


type Recovery
    = Recoverable
    | Unrecoverable


from : Recovery -> ProblemSimple -> Problem
from recovery { title, message } =
    Problem
        { title = title
        , message = message
        , path = Nothing
        , recovery = recovery
        }


withPath : Path -> Problem -> Problem
withPath path (Problem problem) =
    Problem
        { title = problem.title
        , message = problem.message
        , path = Just path
        , recovery = problem.recovery
        }


unwrapFOR_TESTS : Problem -> ProblemSimple
unwrapFOR_TESTS (Problem problem) =
    { title = problem.title
    , message = problem.message
    }


stop : Console -> FormatOptions options -> Problem -> Cmd msg
stop stderr formatOptions problem =
    Cmd.batch
        [ Cli.println stderr (format formatOptions problem)
        , exit formatOptions.attemptFutureRecovery problem
        ]


exit : Bool -> Problem -> Cmd msg
exit watch (Problem problem) =
    case problem.recovery of
        Recoverable ->
            if watch then
                Cmd.none

            else
                Cli.exit 1

        Unrecoverable ->
            Cli.exit 1


type alias FormatOptions a =
    { a
        | color : Color.Support
        , reportMode : ReportMode
        , debug : Bool
        , attemptFutureRecovery : Bool
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


invalidElmJson : String -> ReviewProject -> Decode.Error -> Problem
invalidElmJson pathToElmJson reviewProject error =
    case reviewProject of
        Options.Local _ ->
            { title = "COULD NOT READ ELM.JSON"
            , message = localDecodingErrorMessage pathToElmJson error
            }
                |> from Recoverable
                |> withPath pathToElmJson

        Options.Remote remoteTemplate ->
            { title = "TEMPLATE ELM.JSON PARSING ERROR"
            , message = templateDecodingErrorMessage remoteTemplate error
            }
                |> from Unrecoverable


localDecodingErrorMessage : String -> Decode.Error -> Colorize -> String
localDecodingErrorMessage pathToElmJson error c =
    "I tried reading " ++ c Yellow pathToElmJson ++ """ but encountered a problem while reading it. Please check that it is valid JSON that the Elm compiler would be happy with.

Here is the error I encountered:

""" ++ Decode.errorToString error


templateDecodingErrorMessage : RemoteTemplate -> Decode.Error -> Colorize -> String
templateDecodingErrorMessage remoteTemplate error c =
    "I found the " ++ c Yellow "elm.json" ++ " associated with " ++ c Yellow remoteTemplate.repoName ++ """, but encountered a problem while reading it. Please check that it is valid JSON that the Elm compiler would be happy with.
   
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
        |> from Unrecoverable


notImplementedYet : String -> Problem
notImplementedYet featureDescription =
    { title = "FEATURE IS NOT IMPLEMENTED YET"
    , message = \_ -> featureDescription ++ " is not implemented yet."
    }
        |> from Unrecoverable

module OptionsParserTest exposing (all)

import Dict
import ElmReview.Color as Color
import ElmReview.Problem as Problem
import ElmReview.ReportMode as ReportMode
import Expect exposing (Expectation)
import Test exposing (Test, describe, test)
import Wrapper.Options as Options exposing (ReviewOptions)
import Wrapper.Options.Parser as OptionsParser exposing (OptionsParseResult(..))
import Wrapper.ProjectPaths as ProjectPaths
import Wrapper.Subcommand as Subcommand exposing (Subcommand)


all : Test
all =
    describe "Wrapper.Flags.parse"
        [ test "Parse empty arguments" <|
            \() ->
                { env = Dict.empty
                , args = []
                }
                    |> OptionsParser.parse
                    |> expectReview emptyOptions
        , test "Parse subcommand init" <|
            \() ->
                { env = Dict.empty
                , args = [ "init" ]
                }
                    |> OptionsParser.parse
                    |> expectReview { emptyOptions | subcommand = Just Subcommand.Init }
        , test "Consider unknown args as directories to analyze" <|
            \() ->
                { env = Dict.empty
                , args = [ "unknown", "other" ]
                }
                    |> OptionsParser.parse
                    |> expectReview { emptyOptions | reviewAppFlags = [ "--dirs-to-analyze=other,unknown" ] }
        , test "Enter help mode if --help is used" <|
            \() ->
                { env = Dict.empty
                , args = [ "--help" ]
                }
                    |> OptionsParser.parse
                    |> expectHelp Nothing
        , test "Enter help mode for init if `init --help` is used" <|
            \() ->
                { env = Dict.empty
                , args = [ "init", "--help" ]
                }
                    |> OptionsParser.parse
                    |> expectHelp (Just Subcommand.Init)
        , test "--help can be used before the subcommand" <|
            \() ->
                { env = Dict.empty
                , args = [ "--help", "init" ]
                }
                    |> OptionsParser.parse
                    |> expectHelp (Just Subcommand.Init)
        , test "Enter help mode by using the -h shorthand" <|
            \() ->
                { env = Dict.empty
                , args = [ "-h" ]
                }
                    |> OptionsParser.parse
                    |> expectHelp Nothing
        , test "Enter version mode by using --version" <|
            \() ->
                { env = Dict.empty
                , args = [ "--version" ]
                }
                    |> OptionsParser.parse
                    |> Expect.equal ShowVersion
        , test "Enter version mode by using the -v shorthand" <|
            \() ->
                { env = Dict.empty
                , args = [ "-v" ]
                }
                    |> OptionsParser.parse
                    |> Expect.equal ShowVersion
        ]


emptyOptions : ReviewOptions
emptyOptions =
    { subcommand = Nothing
    , projectPaths =
        ProjectPaths.from
            { projectRoot = "."
            , namespace = "cli"
            }
    , forceBuild = False
    , color = Color.yesColors
    , debug = False
    , report = ReportMode.HumanReadable
    , reviewProject = Options.Local "review"
    , reviewAppFlags = []
    }


expectReview : ReviewOptions -> OptionsParseResult -> Expectation
expectReview expected received =
    case received of
        Review result ->
            Expect.equal expected result

        NeedElmJsonPath { toOptions } ->
            expectReview expected (toOptions { elmJsonPath = "elm.json" })

        ShowVersion ->
            Expect.fail "Unexpected showing of version"

        ShowHelp { subcommand } ->
            Expect.fail ("Unexpected showing of help with subcommand " ++ Debug.toString subcommand)

        Init options ->
            Expect.fail ("Unexpected parsing of init subcommand " ++ Debug.toString options)

        ParseError _ problem ->
            let
                { title, message } =
                    Problem.unwrapFOR_TESTS problem
            in
            Expect.fail ("Unexpected parsing failure:\n\n" ++ title ++ "\n\n" ++ message (Color.toAnsi Color.noColors))


expectHelp : Maybe Subcommand -> OptionsParseResult -> Expectation
expectHelp expectedSubcommand received =
    case received of
        ShowHelp { subcommand } ->
            Expect.equal expectedSubcommand subcommand

        ShowVersion ->
            Expect.fail "Unexpected showing of version"

        Review _ ->
            Expect.fail "Unexpected parse success without help"

        Init options ->
            Expect.fail ("Unexpected parsing of init subcommand " ++ Debug.toString options)

        NeedElmJsonPath _ ->
            Expect.fail "Unexpected parse success without help"

        ParseError _ problem ->
            let
                { title, message } =
                    Problem.unwrapFOR_TESTS problem
            in
            Expect.fail ("Unexpected parsing failure:\n\n" ++ title ++ "\n\n" ++ message (Color.toAnsi Color.noColors))

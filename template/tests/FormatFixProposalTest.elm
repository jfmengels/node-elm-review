module FormatFixProposalTest exposing (suite)

import Dict
import Elm.Review.Reporter as Reporter exposing (Error, File)
import FormatTester exposing (expect)
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "formatFixProposal"
        [ test "propose fix where the diff is only a single segment" <|
            \() ->
                let
                    error : Error
                    error =
                        { ruleName = "NoDebug"
                        , ruleLink = Just "https://package.elm-lang.org/packages/author/package/1.0.0/NoDebug"
                        , message = "Do not use Debug"
                        , details =
                            [ "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum."
                            , "Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula."
                            ]
                        , range =
                            { start = { row = 2, column = 5 }
                            , end = { row = 2, column = 10 }
                            }
                        , fixesHash = Just "some-value"
                        , suppressed = False
                        }

                    file : File
                    file =
                        { path = Reporter.FilePath "src/FileA.elm"
                        , source = Reporter.Source """module FileA exposing (a)
a = Debug.log "debug" 1
other=lines
other2=lines2
"""
                        }

                    fixedSource : Reporter.Source
                    fixedSource =
                        Reporter.Source """module FileA exposing (a)
a = 1
other=lines
other2=lines2
"""
                in
                Reporter.formatFixProposal Dict.empty Reporter.WithDetails file error fixedSource
                    |> expect
                        { withoutColors = """-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5

NoDebug: Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       ^^^^^
3| other=lines

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum.

Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula.

I think I can fix this. Here is my proposal:

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
3| a = 1
3| other=lines
"""
                        , withColors = """[-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5](#33BBC8)

[NoDebug](#FF0000): Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       [^^^^^](#FF0000)
3| other=lines

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum.

Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula.

[I think I can fix this. Here is my proposal:](#33BBC8)

1| module FileA exposing (a)
[2| a = Debug.log "debug" 1](#FF0000)
[3| a = 1](#008000)
3| other=lines
"""
                        }
        , test "propose fix where the diff contains blank lines" <|
            \() ->
                let
                    error : Error
                    error =
                        { ruleName = "Some.Rule.Name"
                        , ruleLink = Just "https://package.elm-lang.org/packages/author/package/1.0.0/Some-Rule-Name"
                        , message = "Some message"
                        , details = [ "Some details" ]
                        , range =
                            { start = { row = 2, column = 1 }
                            , end = { row = 2, column = 2 }
                            }
                        , fixesHash = Just "some-value"
                        , suppressed = False
                        }

                    file : File
                    file =
                        { path = Reporter.FilePath "src/Some/File.elm"
                        , source = Reporter.Source """module Some.File exposing (a)
a =
    1

b =
    a
"""
                        }

                    fixedSource : Reporter.Source
                    fixedSource =
                        Reporter.Source """module Some.File exposing (a)


b =
    a
"""
                in
                Reporter.formatFixProposal Dict.empty Reporter.WithDetails file error fixedSource
                    |> expect
                        { withoutColors =
                            """-- ELM-REVIEW ERROR -------------------------------------- src/Some/File.elm:2:1

Some.Rule.Name: Some message

1| module Some.File exposing (a)
2| a =
   ^
3|     1

Some details

I think I can fix this. Here is my proposal:

1| module Some.File exposing (a)
2| a =
3|     1
4| """ ++ "\n5| " ++ """
5| b =
"""
                        , withColors =
                            """[-- ELM-REVIEW ERROR -------------------------------------- src/Some/File.elm:2:1](#33BBC8)

[Some.Rule.Name](#FF0000): Some message

1| module Some.File exposing (a)
2| a =
   [^](#FF0000)
3|     1

Some details

[I think I can fix this. Here is my proposal:](#33BBC8)

1| module Some.File exposing (a)
[2| a =](#FF0000)
[3|     1](#FF0000)
4| """ ++ """
[5| ](#008000)
5| b =
"""
                        }
        ]

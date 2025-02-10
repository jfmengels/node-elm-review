module ReporterTest exposing (multipleErrorsIncludingGlobalErrorTest, suite)

import Elm.Review.FixExplanation as FixExplanation exposing (FixExplanation)
import Elm.Review.Reporter as Reporter
import Elm.Review.SuppressedErrors as SuppressedErrors exposing (SuppressedErrors)
import Elm.Review.UnsuppressMode as UnsuppressMode
import Expect exposing (Expectation)
import FormatTester exposing (expect)
import Review.Fix as Edit
import Review.Fix.FixProblem as FixProblem exposing (FixProblem)
import Set
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "formatReport"
        [ noErrorTest
        , noErrorButPreviousTest
        , singleErrorTest
        , multipleErrorsTests
        , fixAvailableTest
        , singleCompactErrorTest
        , multilineErrorTest
        , globalErrorTest
        , suppressedTests
        , unicodeTests
        ]


noErrorTest : Test
noErrorTest =
    test "report that all is fine when there are no errors" <|
        \() ->
            [ { path = Reporter.FilePath "src/FileA.elm"
              , source = Reporter.Source """module FileA exposing (a)
a = Debug.log "debug" 1"""
              , errors = []
              }
            , { path = Reporter.FilePath "src/FileB.elm"
              , source = Reporter.Source """module FileB exposing (a)
a = Debug.log "debug" 1"""
              , errors = []
              }
            ]
                |> Reporter.formatReport
                    { suppressedErrors = SuppressedErrors.empty
                    , unsuppressMode = UnsuppressMode.UnsuppressNone
                    , originalNumberOfSuppressedErrors = 0
                    , detailsMode = Reporter.WithDetails
                    , fixExplanation = FixExplanation.Succinct
                    , mode = Reporter.Reviewing
                    , errorsHaveBeenFixedPreviously = False
                    }
                |> expect
                    { withoutColors = "I found no errors!"
                    , withColors = "I found no errors!"
                    }


noErrorButPreviousTest : Test
noErrorButPreviousTest =
    test "report that all is fine when there are no errors but some have been fixed" <|
        \() ->
            [ { path = Reporter.FilePath "src/FileA.elm"
              , source = Reporter.Source """module FileA exposing (a)
a = Debug.log "debug" 1"""
              , errors = []
              }
            , { path = Reporter.FilePath "src/FileB.elm"
              , source = Reporter.Source """module FileB exposing (a)
a = Debug.log "debug" 1"""
              , errors = []
              }
            ]
                |> Reporter.formatReport
                    { suppressedErrors = SuppressedErrors.empty
                    , unsuppressMode = UnsuppressMode.UnsuppressNone
                    , originalNumberOfSuppressedErrors = 0
                    , detailsMode = Reporter.WithDetails
                    , fixExplanation = FixExplanation.Succinct
                    , mode = Reporter.Reviewing
                    , errorsHaveBeenFixedPreviously = True
                    }
                |> expect
                    { withoutColors = "I found no more errors!"
                    , withColors = "I found no more errors!"
                    }


singleErrorTest : Test
singleErrorTest =
    test "report a single error in a file" <|
        \() ->
            [ { path = Reporter.FilePath "src/FileA.elm"
              , source = Reporter.Source """module FileA exposing (a)
a = Debug.log "debug" 1"""
              , errors =
                    [ { ruleName = "NoDebug"
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
                      , providesFix = False
                      , fixProblem = Nothing
                      , providesFileRemovalFix = False
                      , suppressed = False
                      }
                    ]
              }
            , { path = Reporter.FilePath "src/FileB.elm"
              , source = Reporter.Source """module FileB exposing (a)
a = Debug.log "debug" 1"""
              , errors = []
              }
            ]
                |> Reporter.formatReport
                    { suppressedErrors = SuppressedErrors.empty
                    , unsuppressMode = UnsuppressMode.UnsuppressNone
                    , originalNumberOfSuppressedErrors = 0
                    , detailsMode = Reporter.WithDetails
                    , fixExplanation = FixExplanation.Succinct
                    , mode = Reporter.Reviewing
                    , errorsHaveBeenFixedPreviously = False
                    }
                |> expect
                    { withoutColors = """-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5

NoDebug: Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       ^^^^^

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum.

Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula.

I found 1 error in 1 file."""
                    , withColors = """[-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5](#33BBC8)

[NoDebug](#FF0000): Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       [^^^^^](#FF0000)

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum.

Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula.

I found [1 error](#FF0000) in [1 file](#E8C338)."""
                    }


singleCompactErrorTest : Test
singleCompactErrorTest =
    test "report a single error in a file in compact mode" <|
        \() ->
            [ { path = Reporter.FilePath "src/FileA.elm"
              , source = Reporter.Source """module FileA exposing (a)
a = Debug.log "debug" 1"""
              , errors =
                    [ { ruleName = "NoDebug"
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
                      , providesFix = False
                      , fixProblem = Nothing
                      , providesFileRemovalFix = False
                      , suppressed = False
                      }
                    ]
              }
            , { path = Reporter.FilePath "src/FileB.elm"
              , source = Reporter.Source """module FileB exposing (a)
a = Debug.log "debug" 1"""
              , errors = []
              }
            ]
                |> Reporter.formatReport
                    { suppressedErrors = SuppressedErrors.empty
                    , unsuppressMode = UnsuppressMode.UnsuppressNone
                    , originalNumberOfSuppressedErrors = 0
                    , detailsMode = Reporter.WithoutDetails
                    , fixExplanation = FixExplanation.Succinct
                    , mode = Reporter.Reviewing
                    , errorsHaveBeenFixedPreviously = False
                    }
                |> expect
                    { withoutColors = """-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5

NoDebug: Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       ^^^^^

I found 1 error in 1 file."""
                    , withColors = """[-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5](#33BBC8)

[NoDebug](#FF0000): Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       [^^^^^](#FF0000)

I found [1 error](#FF0000) in [1 file](#E8C338)."""
                    }


multilineErrorTest : Test
multilineErrorTest =
    test "report a single error spanning multiple lines" <|
        \() ->
            [ { path = Reporter.FilePath "src/FileA.elm"
              , source = Reporter.Source """module FileA exposing (a)


a =
    floor <|
        1.2


            + 3.4
            + 5.6 + ignore

-- end
"""
              , errors =
                    [ { ruleName = "NoLeftPizza"
                      , ruleLink = Just "https://package.elm-lang.org/packages/author/package/1.0.0/NoLeftPizza"
                      , message = "Do not use left pizza"
                      , details = []
                      , range =
                            { start = { row = 5, column = 5 }
                            , end = { row = 10, column = 18 }
                            }
                      , providesFix = False
                      , fixProblem = Nothing
                      , providesFileRemovalFix = False
                      , suppressed = False
                      }
                    ]
              }
            ]
                |> Reporter.formatReport
                    { suppressedErrors = SuppressedErrors.empty
                    , unsuppressMode = UnsuppressMode.UnsuppressNone
                    , originalNumberOfSuppressedErrors = 0
                    , detailsMode = Reporter.WithoutDetails
                    , fixExplanation = FixExplanation.Succinct
                    , mode = Reporter.Reviewing
                    , errorsHaveBeenFixedPreviously = False
                    }
                |> expect
                    { withoutColors = """-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:5:5

NoLeftPizza: Do not use left pizza

 4| a =
 5|     floor <|
        ^^^^^^^^
 6|         1.2
            ^^^
 7|
 8|
 9|             + 3.4
                ^^^^^
10|             + 5.6 + ignore
                ^^^^^

I found 1 error in 1 file."""
                    , withColors = """[-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:5:5](#33BBC8)

[NoLeftPizza](#FF0000): Do not use left pizza

 4| a =
 5|     floor <|
        [^^^^^^^^](#FF0000)
 6|         1.2
            [^^^](#FF0000)
 7|
 8|
 9|             + 3.4
                [^^^^^](#FF0000)
10|             + 5.6 + ignore
                [^^^^^](#FF0000)

I found [1 error](#FF0000) in [1 file](#E8C338)."""
                    }


multipleErrorsTests : Test
multipleErrorsTests =
    describe "multiple errors"
        [ test "report multiple errors in a file" <|
            \() ->
                let
                    details : List String
                    details =
                        [ "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum."
                        , "Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula."
                        ]
                in
                [ { path = Reporter.FilePath "src/FileA.elm"
                  , source = Reporter.Source """module FileA exposing (a)
a = Debug.log "debug" 1
b = foo <| Debug.log "other debug" 1"""
                  , errors =
                        [ { ruleName = "NoDebug"
                          , ruleLink = Just "https://package.elm-lang.org/packages/author/package/1.0.0/NoDebug"
                          , message = "Do not use Debug"
                          , details = details
                          , range =
                                { start = { row = 2, column = 5 }
                                , end = { row = 2, column = 10 }
                                }
                          , providesFix = False
                          , fixProblem = Nothing
                          , providesFileRemovalFix = False
                          , suppressed = False
                          }
                        , { ruleName = "NoDebug"
                          , ruleLink = Just "https://package.elm-lang.org/packages/author/package/1.0.0/NoDebug"
                          , message = "Do not use Debug"
                          , details = details
                          , range =
                                { start = { row = 3, column = 12 }
                                , end = { row = 3, column = 17 }
                                }
                          , providesFix = False
                          , fixProblem = Nothing
                          , providesFileRemovalFix = False
                          , suppressed = False
                          }
                        ]
                  }
                , { path = Reporter.FilePath "src/FileB.elm"
                  , source = Reporter.Source """module FileB exposing (a)
a = Debug.log "debug" 1"""
                  , errors = []
                  }
                ]
                    |> Reporter.formatReport
                        { suppressedErrors = SuppressedErrors.empty
                        , unsuppressMode = UnsuppressMode.UnsuppressNone
                        , originalNumberOfSuppressedErrors = 0
                        , detailsMode = Reporter.WithDetails
                        , fixExplanation = FixExplanation.Succinct
                        , mode = Reporter.Reviewing
                        , errorsHaveBeenFixedPreviously = False
                        }
                    |> expect
                        { withoutColors = """-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5

NoDebug: Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       ^^^^^
3| b = foo <| Debug.log "other debug" 1

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum.

Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula.

───────────────────────────────────────────────────────────── src/FileA.elm:3:12

NoDebug: Do not use Debug

2| a = Debug.log "debug" 1
3| b = foo <| Debug.log "other debug" 1
              ^^^^^

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum.

Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula.

I found 2 errors in 1 file."""
                        , withColors = """[-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5](#33BBC8)

[NoDebug](#FF0000): Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       [^^^^^](#FF0000)
3| b = foo <| Debug.log "other debug" 1

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum.

Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula.

───────────────────────────────────────────────────────────── src/FileA.elm:3:12

[NoDebug](#FF0000): Do not use Debug

2| a = Debug.log "debug" 1
3| b = foo <| Debug.log "other debug" 1
              [^^^^^](#FF0000)

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum.

Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula.

I found [2 errors](#FF0000) in [1 file](#E8C338)."""
                        }
        , test "report errors in multiple files" <|
            \() ->
                [ { path = Reporter.FilePath "src/FileA.elm"
                  , source = Reporter.Source """module FileA exposing (a)
a = Debug.log "debug" 1"""
                  , errors =
                        [ { ruleName = "NoDebug"
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
                          , providesFix = False
                          , fixProblem = Nothing
                          , providesFileRemovalFix = False
                          , suppressed = False
                          }
                        ]
                  }
                , { path = Reporter.FilePath "src/FileB.elm"
                  , source = Reporter.Source """module FileB exposing (a)
a = Debug.log "debug" 1"""
                  , errors =
                        [ { ruleName = "NoDebug"
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
                          , providesFix = False
                          , fixProblem = Nothing
                          , providesFileRemovalFix = False
                          , suppressed = False
                          }
                        ]
                  }
                , { path = Reporter.FilePath "src/FileC.elm"
                  , source = Reporter.Source """module FileC exposing (a)
a = Debug.log "debug" 1"""
                  , errors =
                        [ { ruleName = "NoDebug"
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
                          , providesFix = False
                          , fixProblem = Nothing
                          , providesFileRemovalFix = False
                          , suppressed = False
                          }
                        ]
                  }
                ]
                    |> Reporter.formatReport
                        { suppressedErrors = SuppressedErrors.empty
                        , unsuppressMode = UnsuppressMode.UnsuppressNone
                        , originalNumberOfSuppressedErrors = 0
                        , detailsMode = Reporter.WithDetails
                        , fixExplanation = FixExplanation.Succinct
                        , mode = Reporter.Reviewing
                        , errorsHaveBeenFixedPreviously = False
                        }
                    |> expect
                        { withoutColors = """-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5

NoDebug: Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       ^^^^^

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum.

Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula.

                                                            src/FileA.elm  ↑
====o======================================================================o====
    ↓  src/FileB.elm


-- ELM-REVIEW ERROR ------------------------------------------ src/FileB.elm:2:5

NoDebug: Do not use Debug

1| module FileB exposing (a)
2| a = Debug.log "debug" 1
       ^^^^^

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum.

Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula.

                                                            src/FileB.elm  ↑
====o======================================================================o====
    ↓  src/FileC.elm


-- ELM-REVIEW ERROR ------------------------------------------ src/FileC.elm:2:5

NoDebug: Do not use Debug

1| module FileC exposing (a)
2| a = Debug.log "debug" 1
       ^^^^^

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum.

Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula.

I found 3 errors in 3 files."""
                        , withColors = """[-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5](#33BBC8)

[NoDebug](#FF0000): Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       [^^^^^](#FF0000)

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum.

Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula.

                                                            [src/FileA.elm  ↑
====o======================================================================o====
    ↓  src/FileB.elm](#FF0000)


[-- ELM-REVIEW ERROR ------------------------------------------ src/FileB.elm:2:5](#33BBC8)

[NoDebug](#FF0000): Do not use Debug

1| module FileB exposing (a)
2| a = Debug.log "debug" 1
       [^^^^^](#FF0000)

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum.

Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula.

                                                            [src/FileB.elm  ↑
====o======================================================================o====
    ↓  src/FileC.elm](#FF0000)


[-- ELM-REVIEW ERROR ------------------------------------------ src/FileC.elm:2:5](#33BBC8)

[NoDebug](#FF0000): Do not use Debug

1| module FileC exposing (a)
2| a = Debug.log "debug" 1
       [^^^^^](#FF0000)

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum.

Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula.

I found [3 errors](#FF0000) in [3 files](#E8C338)."""
                        }
        ]


fixAvailableTest : Test
fixAvailableTest =
    describe "Fixing mention"
        [ test "should mention a fix is available when the error provides one" <|
            \() ->
                [ { path = Reporter.FilePath "src/FileA.elm"
                  , source = Reporter.Source """module FileA exposing (a)
a = Debug.log "debug" 1"""
                  , errors =
                        [ { ruleName = "NoDebug"
                          , ruleLink = Just "https://package.elm-lang.org/packages/author/package/1.0.0/NoDebug"
                          , message = "Do not use Debug"
                          , details = [ "Details" ]
                          , range =
                                { start = { row = 2, column = 5 }
                                , end = { row = 2, column = 10 }
                                }
                          , providesFix = True
                          , fixProblem = Nothing
                          , providesFileRemovalFix = False
                          , suppressed = False
                          }
                        ]
                  }
                ]
                    |> Reporter.formatReport
                        { suppressedErrors = SuppressedErrors.empty
                        , unsuppressMode = UnsuppressMode.UnsuppressNone
                        , originalNumberOfSuppressedErrors = 0
                        , detailsMode = Reporter.WithDetails
                        , fixExplanation = FixExplanation.Succinct
                        , mode = Reporter.Reviewing
                        , errorsHaveBeenFixedPreviously = False
                        }
                    |> expect
                        { withoutColors = """-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5

(fix) NoDebug: Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       ^^^^^

Details

Errors marked with (fix) can be fixed automatically using `elm-review --fix`.

I found 1 error in 1 file."""
                        , withColors = """[-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5](#33BBC8)

[(fix) ](#33BBC8)[NoDebug](#FF0000): Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       [^^^^^](#FF0000)

Details

[Errors marked with (fix) can be fixed automatically using `elm-review --fix`.](#33BBC8)

I found [1 error](#FF0000) in [1 file](#E8C338)."""
                        }
        , test "should mention a fix is failing when the error provides one in fix mode (succinct)" <|
            \() ->
                [ { path = Reporter.FilePath "src/FileA.elm"
                  , source = Reporter.Source """module FileA exposing (a)
a = Debug.log "debug" 1"""
                  , errors =
                        [ { ruleName = "NoDebug"
                          , ruleLink = Just "https://package.elm-lang.org/packages/author/package/1.0.0/NoDebug"
                          , message = "Do not use Debug"
                          , details = [ "Details" ]
                          , range =
                                { start = { row = 2, column = 5 }
                                , end = { row = 2, column = 10 }
                                }
                          , providesFix = True
                          , fixProblem =
                                FixProblem.HasCollisionsInEditRanges
                                    { filePath = "src/FileA.elm"
                                    , edits =
                                        [ Edit.removeRange { start = { row = 2, column = 4 }, end = { row = 2, column = 10 } }
                                        , Edit.removeRange { start = { row = 2, column = 6 }, end = { row = 2, column = 12 } }
                                        ]
                                    }
                                    |> Just
                          , providesFileRemovalFix = False
                          , suppressed = False
                          }
                        ]
                  }
                ]
                    |> Reporter.formatReport
                        { suppressedErrors = SuppressedErrors.empty
                        , unsuppressMode = UnsuppressMode.UnsuppressNone
                        , originalNumberOfSuppressedErrors = 0
                        , detailsMode = Reporter.WithDetails
                        , fixExplanation = FixExplanation.Succinct
                        , mode = Reporter.Fixing False
                        , errorsHaveBeenFixedPreviously = False
                        }
                    |> expect
                        { withoutColors = """-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5

(FIX FAILED) NoDebug: Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       ^^^^^

Details

I failed to apply the automatic fix because it contained edits with collisions.

I tried applying some fixes but they failed in ways the author(s) didn't expect. Please let the author(s) of the following rules know:
- NoDebug (https://github.com/author/package/issues)

Before doing so, I highly recommend re-running `elm-review` with `--explain-fix-failure`, which would provide more information which could help solve the issue.

I found 1 error in 1 file."""
                        , withColors = """[-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5](#33BBC8)

[(FIX FAILED) ](#E8C338)[NoDebug](#FF0000): Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       [^^^^^](#FF0000)

Details

[I failed to apply the automatic fix because it contained edits with collisions.](#E8C338)

[I tried applying some fixes but they failed in ways the author(s) didn't expect. Please let the author(s) of the following rules know:
- NoDebug (https://github.com/author/package/issues)

Before doing so, I highly recommend re-running `elm-review` with `--explain-fix-failure`, which would provide more information which could help solve the issue.](#E8C338)

I found [1 error](#FF0000) in [1 file](#E8C338)."""
                        }
        , test "should mention a fix is failing when the error provides one in fix mode (detailed)" <|
            \() ->
                [ { path = Reporter.FilePath "src/FileA.elm"
                  , source = Reporter.Source """module FileA exposing (a)
a = Debug.log "debug" 1"""
                  , errors =
                        [ { ruleName = "NoDebug"
                          , ruleLink = Just "https://package.elm-lang.org/packages/author/package/1.0.0/NoDebug"
                          , message = "Do not use Debug"
                          , details = [ "Details" ]
                          , range =
                                { start = { row = 2, column = 5 }
                                , end = { row = 2, column = 10 }
                                }
                          , providesFix = True
                          , fixProblem =
                                FixProblem.HasCollisionsInEditRanges
                                    { filePath = "src/FileA.elm"
                                    , edits =
                                        [ Edit.removeRange { start = { row = 2, column = 4 }, end = { row = 2, column = 10 } }
                                        , Edit.removeRange { start = { row = 2, column = 6 }, end = { row = 2, column = 12 } }
                                        ]
                                    }
                                    |> Just
                          , providesFileRemovalFix = False
                          , suppressed = False
                          }
                        ]
                  }
                ]
                    |> Reporter.formatReport
                        { suppressedErrors = SuppressedErrors.empty
                        , unsuppressMode = UnsuppressMode.UnsuppressNone
                        , originalNumberOfSuppressedErrors = 0
                        , detailsMode = Reporter.WithDetails
                        , fixExplanation = FixExplanation.Detailed
                        , mode = Reporter.Fixing False
                        , errorsHaveBeenFixedPreviously = False
                        }
                    |> expect
                        { withoutColors = """-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5

(FIX FAILED) NoDebug: Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       ^^^^^

Details

I failed to apply the automatic fix because some edits for src/FileA.elm collide:

    Review.Fix.removeRange
         { start = { row = 2, column = 4 }, end = { row = 2, column = 10 } }

    Review.Fix.removeRange
         { start = { row = 2, column = 6 }, end = { row = 2, column = 12 } }

I tried applying some fixes but they failed in ways the author(s) didn't expect. Please let the author(s) of the following rules know:
- NoDebug (https://github.com/author/package/issues)

Please try to provide a SSCCE (https://sscce.org/) and as much information as possible to help solve the issue.

I found 1 error in 1 file."""
                        , withColors = """[-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5](#33BBC8)

[(FIX FAILED) ](#E8C338)[NoDebug](#FF0000): Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       [^^^^^](#FF0000)

Details

[I failed to apply the automatic fix because some edits for src/FileA.elm collide:

    Review.Fix.removeRange
         { start = { row = 2, column = 4 }, end = { row = 2, column = 10 } }

    Review.Fix.removeRange
         { start = { row = 2, column = 6 }, end = { row = 2, column = 12 } }](#E8C338)

[I tried applying some fixes but they failed in ways the author(s) didn't expect. Please let the author(s) of the following rules know:
- NoDebug (https://github.com/author/package/issues)

Please try to provide a SSCCE (https://sscce.org/) and as much information as possible to help solve the issue.](#E8C338)

I found [1 error](#FF0000) in [1 file](#E8C338)."""
                        }
        , test "should mention an error's fix fails when it's known in review mode" <|
            \() ->
                [ { path = Reporter.FilePath "src/FileA.elm"
                  , source = Reporter.Source """module FileA exposing (a)
a = Debug.log "debug" 1"""
                  , errors =
                        [ { ruleName = "NoDebug"
                          , ruleLink = Just "https://package.elm-lang.org/packages/author/package/1.0.0/NoDebug"
                          , message = "Do not use Debug"
                          , details = [ "Details" ]
                          , range =
                                { start = { row = 2, column = 5 }
                                , end = { row = 2, column = 10 }
                                }
                          , providesFix = True
                          , fixProblem =
                                Just
                                    (FixProblem.HasCollisionsInEditRanges
                                        { filePath = "src/FileA.elm"
                                        , edits =
                                            [ Edit.removeRange { start = { row = 2, column = 4 }, end = { row = 2, column = 10 } }
                                            , Edit.removeRange { start = { row = 2, column = 6 }, end = { row = 2, column = 12 } }
                                            ]
                                        }
                                    )
                          , providesFileRemovalFix = False
                          , suppressed = False
                          }
                        ]
                  }
                ]
                    |> Reporter.formatReport
                        { suppressedErrors = SuppressedErrors.empty
                        , unsuppressMode = UnsuppressMode.UnsuppressNone
                        , originalNumberOfSuppressedErrors = 0
                        , detailsMode = Reporter.WithDetails
                        , fixExplanation = FixExplanation.Succinct
                        , mode = Reporter.Reviewing
                        , errorsHaveBeenFixedPreviously = False
                        }
                    |> expect
                        { withoutColors = """-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5

(failing fix) NoDebug: Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       ^^^^^

Details

I found 1 error in 1 file."""
                        , withColors = """[-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5](#33BBC8)

[(failing fix) ](#E8C338)[NoDebug](#FF0000): Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       [^^^^^](#FF0000)

Details

I found [1 error](#FF0000) in [1 file](#E8C338)."""
                        }
        , test "should show a failing fix that has collisions in edit ranges (succinct)" <|
            \() ->
                expectFixFailure
                    FixExplanation.Succinct
                    (FixProblem.HasCollisionsInEditRanges
                        { filePath = "src/FileA.elm"
                        , edits =
                            [ Edit.removeRange { start = { row = 2, column = 4 }, end = { row = 2, column = 10 } }
                            , Edit.removeRange { start = { row = 2, column = 6 }, end = { row = 2, column = 12 } }
                            ]
                        }
                    )
                    { withoutColors = """I failed to apply the automatic fix because it contained edits with collisions.

I tried applying some fixes but they failed in ways the author(s) didn't expect. Please let the author(s) of the following rules know:
- NoDebug (https://github.com/author/package/issues)

Before doing so, I highly recommend re-running `elm-review` with `--explain-fix-failure`, which would provide more information which could help solve the issue."""
                    , withColors = """[I failed to apply the automatic fix because it contained edits with collisions.](#E8C338)

[I tried applying some fixes but they failed in ways the author(s) didn't expect. Please let the author(s) of the following rules know:
- NoDebug (https://github.com/author/package/issues)

Before doing so, I highly recommend re-running `elm-review` with `--explain-fix-failure`, which would provide more information which could help solve the issue.](#E8C338)"""
                    }
        , test "should show a failing fix that has collisions in edit ranges (detailed)" <|
            \() ->
                expectFixFailure
                    FixExplanation.Detailed
                    (FixProblem.HasCollisionsInEditRanges
                        { filePath = "src/FileA.elm"
                        , edits =
                            [ Edit.removeRange { start = { row = 2, column = 4 }, end = { row = 2, column = 10 } }
                            , Edit.removeRange { start = { row = 2, column = 6 }, end = { row = 2, column = 12 } }
                            ]
                        }
                    )
                    { withoutColors = """I failed to apply the automatic fix because some edits for src/FileA.elm collide:

    Review.Fix.removeRange
         { start = { row = 2, column = 4 }, end = { row = 2, column = 10 } }

    Review.Fix.removeRange
         { start = { row = 2, column = 6 }, end = { row = 2, column = 12 } }

I tried applying some fixes but they failed in ways the author(s) didn't expect. Please let the author(s) of the following rules know:
- NoDebug (https://github.com/author/package/issues)

Please try to provide a SSCCE (https://sscce.org/) and as much information as possible to help solve the issue."""
                    , withColors = """[I failed to apply the automatic fix because some edits for src/FileA.elm collide:

    Review.Fix.removeRange
         { start = { row = 2, column = 4 }, end = { row = 2, column = 10 } }

    Review.Fix.removeRange
         { start = { row = 2, column = 6 }, end = { row = 2, column = 12 } }](#E8C338)

[I tried applying some fixes but they failed in ways the author(s) didn't expect. Please let the author(s) of the following rules know:
- NoDebug (https://github.com/author/package/issues)

Please try to provide a SSCCE (https://sscce.org/) and as much information as possible to help solve the issue.](#E8C338)"""
                    }
        , test "should show a failing fix that has negative ranges (succinct)" <|
            \() ->
                expectFixFailure
                    FixExplanation.Succinct
                    (FixProblem.EditWithNegativeRange
                        { filePath = "src/FileA.elm"
                        , edit = Edit.removeRange { start = { row = 2, column = 10 }, end = { row = 2, column = 4 } }
                        }
                    )
                    { withoutColors = """I failed to apply the automatic fix because it contained edits with negative ranges.

I tried applying some fixes but they failed in ways the author(s) didn't expect. Please let the author(s) of the following rules know:
- NoDebug (https://github.com/author/package/issues)

Before doing so, I highly recommend re-running `elm-review` with `--explain-fix-failure`, which would provide more information which could help solve the issue."""
                    , withColors = """[I failed to apply the automatic fix because it contained edits with negative ranges.](#E8C338)

[I tried applying some fixes but they failed in ways the author(s) didn't expect. Please let the author(s) of the following rules know:
- NoDebug (https://github.com/author/package/issues)

Before doing so, I highly recommend re-running `elm-review` with `--explain-fix-failure`, which would provide more information which could help solve the issue.](#E8C338)"""
                    }
        , test "should show a failing fix that has negative ranges (detailed)" <|
            \() ->
                expectFixFailure
                    FixExplanation.Detailed
                    (FixProblem.EditWithNegativeRange
                        { filePath = "src/FileA.elm"
                        , edit = Edit.removeRange { start = { row = 2, column = 10 }, end = { row = 2, column = 4 } }
                        }
                    )
                    { withoutColors = """I failed to apply the automatic fix because I have found an edit for src/FileA.elm where the start is positioned after the end:

  Review.Fix.removeRange
         { start = { row = 2, column = 10 }, end = { row = 2, column = 4 } }

I tried applying some fixes but they failed in ways the author(s) didn't expect. Please let the author(s) of the following rules know:
- NoDebug (https://github.com/author/package/issues)

Please try to provide a SSCCE (https://sscce.org/) and as much information as possible to help solve the issue."""
                    , withColors = """[I failed to apply the automatic fix because I have found an edit for src/FileA.elm where the start is positioned after the end:

  Review.Fix.removeRange
         { start = { row = 2, column = 10 }, end = { row = 2, column = 4 } }](#E8C338)

[I tried applying some fixes but they failed in ways the author(s) didn't expect. Please let the author(s) of the following rules know:
- NoDebug (https://github.com/author/package/issues)

Please try to provide a SSCCE (https://sscce.org/) and as much information as possible to help solve the issue.](#E8C338)"""
                    }
        , test "should show a failing fix that has import cycles (succinct)" <|
            \() ->
                expectFixFailure
                    FixExplanation.Succinct
                    (FixProblem.CreatesImportCycle [ "Module1", "Module2", "Module3" ])
                    { withoutColors = """I failed to apply the automatic fix because it resulted in an import cycle.

I tried applying some fixes but they failed in ways the author(s) didn't expect. Please let the author(s) of the following rules know:
- NoDebug (https://github.com/author/package/issues)

Before doing so, I highly recommend re-running `elm-review` with `--explain-fix-failure`, which would provide more information which could help solve the issue."""
                    , withColors = """[I failed to apply the automatic fix because it resulted in an import cycle.](#E8C338)

[I tried applying some fixes but they failed in ways the author(s) didn't expect. Please let the author(s) of the following rules know:
- NoDebug (https://github.com/author/package/issues)

Before doing so, I highly recommend re-running `elm-review` with `--explain-fix-failure`, which would provide more information which could help solve the issue.](#E8C338)"""
                    }
        , test "should show a failing fix that has import cycles (detailed)" <|
            \() ->
                expectFixFailure
                    FixExplanation.Detailed
                    (FixProblem.CreatesImportCycle [ "Module1", "Module2", "Module3" ])
                    { withoutColors = """I failed to apply the automatic fix because it resulted in an import cycle.

    ┌─────┐
    │    Module1
    │     ↓
    │    Module2
    │     ↓
    │    Module3
    └─────┘

I tried applying some fixes but they failed in ways the author(s) didn't expect. Please let the author(s) of the following rules know:
- NoDebug (https://github.com/author/package/issues)

Please try to provide a SSCCE (https://sscce.org/) and as much information as possible to help solve the issue."""
                    , withColors = """[I failed to apply the automatic fix because it resulted in an import cycle.](#E8C338)

    ┌─────┐
    │    [Module1](#E8C338)
    │     ↓
    │    [Module2](#E8C338)
    │     ↓
    │    [Module3](#E8C338)
    └─────┘

[I tried applying some fixes but they failed in ways the author(s) didn't expect. Please let the author(s) of the following rules know:
- NoDebug (https://github.com/author/package/issues)

Please try to provide a SSCCE (https://sscce.org/) and as much information as possible to help solve the issue.](#E8C338)"""
                    }
        ]


expectFixFailure : FixExplanation -> FixProblem -> { withoutColors : String, withColors : String } -> Expectation
expectFixFailure fixExplanation fixProblem { withoutColors, withColors } =
    let
        expectedWithoutColorsPrefix : String
        expectedWithoutColorsPrefix =
            """-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5

(FIX FAILED) NoDebug: Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       ^^^^^

Details

"""

        expectedWithColorsPrefix : String
        expectedWithColorsPrefix =
            """[-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5](#33BBC8)

[(FIX FAILED) ](#E8C338)[NoDebug](#FF0000): Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       [^^^^^](#FF0000)

Details

"""

        expectedWithoutColorsSuffix : String
        expectedWithoutColorsSuffix =
            "\n\nI found 1 error in 1 file."

        expectedWithColorsSuffix : String
        expectedWithColorsSuffix =
            "\n\nI found [1 error](#FF0000) in [1 file](#E8C338)."
    in
    [ { path = Reporter.FilePath "src/FileA.elm"
      , source = Reporter.Source """module FileA exposing (a)
a = Debug.log "debug" 1"""
      , errors =
            [ { ruleName = "NoDebug"
              , ruleLink = Just "https://package.elm-lang.org/packages/author/package/1.0.0/NoDebug"
              , message = "Do not use Debug"
              , details = [ "Details" ]
              , range =
                    { start = { row = 2, column = 5 }
                    , end = { row = 2, column = 10 }
                    }
              , providesFix = True
              , fixProblem = Just fixProblem
              , providesFileRemovalFix = False
              , suppressed = False
              }
            ]
      }
    ]
        |> Reporter.formatReport
            { suppressedErrors = SuppressedErrors.empty
            , unsuppressMode = UnsuppressMode.UnsuppressNone
            , originalNumberOfSuppressedErrors = 0
            , detailsMode = Reporter.WithDetails
            , fixExplanation = fixExplanation
            , mode = Reporter.Fixing True
            , errorsHaveBeenFixedPreviously = False
            }
        |> Expect.all
            [ \textList ->
                FormatTester.formatWithoutColors textList
                    |> String.replace expectedWithoutColorsPrefix ""
                    |> String.replace expectedWithoutColorsSuffix ""
                    |> Expect.equal withoutColors
            , \textList ->
                FormatTester.formatWithColors textList
                    |> String.replace expectedWithColorsPrefix ""
                    |> String.replace expectedWithColorsSuffix ""
                    |> Expect.equal withColors
            ]


globalErrorTest : Test
globalErrorTest =
    test "report a global error that has no source code" <|
        \() ->
            [ { path = Reporter.Global
              , source = Reporter.Source ""
              , errors =
                    [ { ruleName = "NoDebug"
                      , ruleLink = Just "https://package.elm-lang.org/packages/author/package/1.0.0/NoDebug"
                      , message = "Do not use Debug"
                      , details =
                            [ "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum."
                            , "Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula."
                            ]
                      , range =
                            { start = { row = 0, column = 0 }
                            , end = { row = 0, column = 0 }
                            }
                      , providesFix = False
                      , fixProblem = Nothing
                      , providesFileRemovalFix = False
                      , suppressed = False
                      }
                    ]
              }
            ]
                |> Reporter.formatReport
                    { suppressedErrors = SuppressedErrors.empty
                    , unsuppressMode = UnsuppressMode.UnsuppressNone
                    , originalNumberOfSuppressedErrors = 0
                    , detailsMode = Reporter.WithoutDetails
                    , fixExplanation = FixExplanation.Succinct
                    , mode = Reporter.Reviewing
                    , errorsHaveBeenFixedPreviously = False
                    }
                |> expect
                    { withoutColors = """-- ELM-REVIEW ERROR ----------------------------------------------- GLOBAL ERROR

NoDebug: Do not use Debug

I found 1 global error."""
                    , withColors = """[-- ELM-REVIEW ERROR ----------------------------------------------- GLOBAL ERROR](#33BBC8)

[NoDebug](#FF0000): Do not use Debug

I found [1 global error](#FF0000)."""
                    }


multipleErrorsIncludingGlobalErrorTest : Test
multipleErrorsIncludingGlobalErrorTest =
    test "report a global error that has no source code" <|
        \() ->
            [ { path = Reporter.Global
              , source = Reporter.Source ""
              , errors =
                    [ { ruleName = "NoDebug"
                      , ruleLink = Just "https://package.elm-lang.org/packages/author/package/1.0.0/NoDebug"
                      , message = "Do not use Debug"
                      , details =
                            [ "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum."
                            , "Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula."
                            ]
                      , range =
                            { start = { row = 0, column = 0 }
                            , end = { row = 0, column = 0 }
                            }
                      , providesFix = False
                      , fixProblem = Nothing
                      , providesFileRemovalFix = False
                      , suppressed = False
                      }
                    ]
              }
            , { path = Reporter.FilePath "src/FileA.elm"
              , source = Reporter.Source """module FileA exposing (a)
a = Debug.log "debug" 1"""
              , errors =
                    [ { ruleName = "NoDebug"
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
                      , providesFix = True
                      , fixProblem = Nothing
                      , providesFileRemovalFix = False
                      , suppressed = True
                      }
                    ]
              }
            ]
                |> Reporter.formatReport
                    { suppressedErrors = SuppressedErrors.empty
                    , unsuppressMode = UnsuppressMode.UnsuppressNone
                    , originalNumberOfSuppressedErrors = 0
                    , detailsMode = Reporter.WithoutDetails
                    , fixExplanation = FixExplanation.Succinct
                    , mode = Reporter.Reviewing
                    , errorsHaveBeenFixedPreviously = False
                    }
                |> expect
                    { withoutColors = """-- ELM-REVIEW ERROR ----------------------------------------------- GLOBAL ERROR

NoDebug: Do not use Debug

                                                                           ↑
====o======================================================================o====
    ↓  src/FileA.elm


-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5

(unsuppressed) (fix) NoDebug: Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       ^^^^^

Errors marked with (unsuppressed) were previously suppressed, but you introduced new errors for the same rule and file. There are now more of those than what I previously allowed. Please fix them until you have at most as many errors as before. Maybe fix a few more while you're there?

Errors marked with (fix) can be fixed automatically using `elm-review --fix`.

I found 1 error in 1 file and 1 global error."""
                    , withColors = """[-- ELM-REVIEW ERROR ----------------------------------------------- GLOBAL ERROR](#33BBC8)

[NoDebug](#FF0000): Do not use Debug

                                                                         [  ↑
====o======================================================================o====
    ↓  src/FileA.elm](#FF0000)


[-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5](#33BBC8)

[(unsuppressed) ](#FFA500)[(fix) ](#33BBC8)[NoDebug](#FF0000): Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       [^^^^^](#FF0000)

[Errors marked with (unsuppressed) were previously suppressed, but you introduced new errors for the same rule and file. There are now more of those than what I previously allowed. Please fix them until you have at most as many errors as before. Maybe fix a few more while you're there?](#FFA500)

[Errors marked with (fix) can be fixed automatically using `elm-review --fix`.](#33BBC8)

I found [1 error](#FF0000) in [1 file](#E8C338) and [1 global error](#FF0000)."""
                    }


suppressedTests : Test
suppressedTests =
    describe "Suppressed"
        [ test "report report that there are no errors but some suppressed errors remain if there are no outstanding errors from the suppressed ones" <|
            \() ->
                let
                    suppressedErrors : SuppressedErrors
                    suppressedErrors =
                        SuppressedErrors.createFOR_TESTS
                            [ ( ( "NoDebug", "src/FileA.elm" ), 1 ) ]
                in
                Reporter.formatReport
                    { suppressedErrors = suppressedErrors
                    , unsuppressMode = UnsuppressMode.UnsuppressNone
                    , originalNumberOfSuppressedErrors = SuppressedErrors.count suppressedErrors
                    , detailsMode = Reporter.WithDetails
                    , fixExplanation = FixExplanation.Succinct
                    , mode = Reporter.Reviewing
                    , errorsHaveBeenFixedPreviously = False
                    }
                    []
                    |> expect
                        { withoutColors = """I found no errors!

There is still 1 suppressed error to address."""
                        , withColors = """I found no errors!

There is still [1 suppressed error](#FFA500) to address."""
                        }
        , test "report report that there are no errors but that the user has fixed some if there are less than the original number of suppressed errors" <|
            \() ->
                let
                    suppressedErrors : SuppressedErrors
                    suppressedErrors =
                        SuppressedErrors.createFOR_TESTS
                            [ ( ( "NoDebug", "src/FileA.elm" ), 2 ) ]
                in
                Reporter.formatReport
                    { suppressedErrors = suppressedErrors
                    , unsuppressMode = UnsuppressMode.UnsuppressNone
                    , originalNumberOfSuppressedErrors = SuppressedErrors.count suppressedErrors + 4
                    , detailsMode = Reporter.WithDetails
                    , fixExplanation = FixExplanation.Succinct
                    , mode = Reporter.Reviewing
                    , errorsHaveBeenFixedPreviously = False
                    }
                    []
                    |> expect
                        { withoutColors = """I found no errors!

There are still 2 suppressed errors to address, and you just fixed 4!"""
                        , withColors = """I found no errors!

There are still [2 suppressed errors](#FFA500) to address, and you just fixed [4](#008000)!"""
                        }
        , test "report report suppressed errors" <|
            \() ->
                [ { path = Reporter.FilePath "src/FileA.elm"
                  , source = Reporter.Source """module FileA exposing (a)
a = Debug.log "debug" 1"""
                  , errors =
                        [ { ruleName = "NoDebug"
                          , ruleLink = Just "https://package.elm-lang.org/packages/author/package/1.0.0/NoDebug"
                          , message = "Do not use Debug"
                          , details = [ "Details" ]
                          , range =
                                { start = { row = 2, column = 5 }
                                , end = { row = 2, column = 10 }
                                }
                          , providesFix = True
                          , fixProblem = Nothing
                          , providesFileRemovalFix = False
                          , suppressed = True
                          }
                        ]
                  }
                ]
                    |> Reporter.formatReport
                        { suppressedErrors = SuppressedErrors.empty
                        , unsuppressMode = UnsuppressMode.UnsuppressNone

                        -- Note: the original number of suppressed errors and the list of those don't matter when errors are shown
                        , originalNumberOfSuppressedErrors = 0
                        , detailsMode = Reporter.WithDetails
                        , fixExplanation = FixExplanation.Succinct
                        , mode = Reporter.Reviewing
                        , errorsHaveBeenFixedPreviously = False
                        }
                    |> expect
                        { withoutColors = """-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5

(unsuppressed) (fix) NoDebug: Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       ^^^^^

Details

Errors marked with (unsuppressed) were previously suppressed, but you introduced new errors for the same rule and file. There are now more of those than what I previously allowed. Please fix them until you have at most as many errors as before. Maybe fix a few more while you're there?

Errors marked with (fix) can be fixed automatically using `elm-review --fix`.

I found 1 error in 1 file."""
                        , withColors = """[-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5](#33BBC8)

[(unsuppressed) ](#FFA500)[(fix) ](#33BBC8)[NoDebug](#FF0000): Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       [^^^^^](#FF0000)

Details

[Errors marked with (unsuppressed) were previously suppressed, but you introduced new errors for the same rule and file. There are now more of those than what I previously allowed. Please fix them until you have at most as many errors as before. Maybe fix a few more while you're there?](#FFA500)

[Errors marked with (fix) can be fixed automatically using `elm-review --fix`.](#33BBC8)

I found [1 error](#FF0000) in [1 file](#E8C338)."""
                        }
        , test "report report all errors when unsuppressMode is UnsuppressAll" <|
            \() ->
                [ { path = Reporter.FilePath "src/FileA.elm"
                  , source = Reporter.Source """module FileA exposing (a)
a = Debug.log "debug" 1"""
                  , errors =
                        [ { ruleName = "NoDebug"
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
                          , providesFix = True
                          , fixProblem = Nothing
                          , providesFileRemovalFix = False
                          , suppressed = True
                          }
                        ]
                  }
                , { path = Reporter.FilePath "src/FileA.elm"
                  , source = Reporter.Source """module FileA exposing (a)
a = Debug.log "debug" 1"""
                  , errors =
                        [ { ruleName = "NoDebug2"
                          , ruleLink = Just "https://package.elm-lang.org/packages/author/package/1.0.0/NoDebug"
                          , message = "Do not use Debug2"
                          , details =
                                [ "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum."
                                , "Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula."
                                ]
                          , range =
                                { start = { row = 2, column = 5 }
                                , end = { row = 2, column = 10 }
                                }
                          , providesFix = True
                          , fixProblem = Nothing
                          , providesFileRemovalFix = False
                          , suppressed = False
                          }
                        ]
                  }
                ]
                    |> Reporter.formatReport
                        { suppressedErrors = SuppressedErrors.empty
                        , unsuppressMode = UnsuppressMode.UnsuppressAll

                        -- Note: the original number of suppressed errors and the list of those don't matter when errors are shown
                        , originalNumberOfSuppressedErrors = 0
                        , detailsMode = Reporter.WithDetails
                        , fixExplanation = FixExplanation.Succinct
                        , mode = Reporter.Reviewing
                        , errorsHaveBeenFixedPreviously = False
                        }
                    |> expect
                        { withoutColors = """-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5

(unsuppressed) (fix) NoDebug: Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       ^^^^^

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum.

Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula.

                                                            src/FileA.elm  ↑
====o======================================================================o====
    ↓  src/FileA.elm


-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5

(fix) NoDebug2: Do not use Debug2

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       ^^^^^

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum.

Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula.

Errors marked with (fix) can be fixed automatically using `elm-review --fix`.

I found 2 errors in 2 files."""
                        , withColors = """[-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5](#33BBC8)

[(unsuppressed) ](#FFA500)[(fix) ](#33BBC8)[NoDebug](#FF0000): Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       [^^^^^](#FF0000)

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum.

Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula.

                                                            [src/FileA.elm  ↑
====o======================================================================o====
    ↓  src/FileA.elm](#FF0000)


[-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5](#33BBC8)

[(fix) ](#33BBC8)[NoDebug2](#FF0000): Do not use Debug2

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       [^^^^^](#FF0000)

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum.

Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula.

[Errors marked with (fix) can be fixed automatically using `elm-review --fix`.](#33BBC8)

I found [2 errors](#FF0000) in [2 files](#E8C338)."""
                        }
        , test "report not show suppressed warning when the rules that report errors are unsuppressed" <|
            \() ->
                [ { path = Reporter.FilePath "src/FileA.elm"
                  , source = Reporter.Source """module FileA exposing (a)
a = Debug.log "debug" 1"""
                  , errors =
                        [ { ruleName = "NoDebug"
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
                          , providesFix = True
                          , fixProblem = Nothing
                          , providesFileRemovalFix = False
                          , suppressed = True
                          }
                        ]
                  }
                , { path = Reporter.FilePath "src/FileA.elm"
                  , source = Reporter.Source """module FileA exposing (a)
a = Debug.log "debug" 1"""
                  , errors =
                        [ { ruleName = "NoDebug2"
                          , ruleLink = Just "https://package.elm-lang.org/packages/author/package/1.0.0/NoDebug"
                          , message = "Do not use Debug2"
                          , details =
                                [ "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum."
                                , "Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula."
                                ]
                          , range =
                                { start = { row = 2, column = 5 }
                                , end = { row = 2, column = 10 }
                                }
                          , providesFix = True
                          , fixProblem = Nothing
                          , providesFileRemovalFix = False
                          , suppressed = False
                          }
                        ]
                  }
                ]
                    |> Reporter.formatReport
                        { suppressedErrors = SuppressedErrors.empty
                        , unsuppressMode = UnsuppressMode.UnsuppressRules (Set.singleton "NoDebug")

                        -- Note: the original number of suppressed errors and the list of those don't matter when errors are shown
                        , originalNumberOfSuppressedErrors = 0
                        , detailsMode = Reporter.WithDetails
                        , fixExplanation = FixExplanation.Succinct
                        , mode = Reporter.Reviewing
                        , errorsHaveBeenFixedPreviously = False
                        }
                    |> expect
                        { withoutColors = """-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5

(unsuppressed) (fix) NoDebug: Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       ^^^^^

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum.

Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula.

                                                            src/FileA.elm  ↑
====o======================================================================o====
    ↓  src/FileA.elm


-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5

(fix) NoDebug2: Do not use Debug2

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       ^^^^^

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum.

Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula.

Errors marked with (fix) can be fixed automatically using `elm-review --fix`.

I found 2 errors in 2 files."""
                        , withColors = """[-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5](#33BBC8)

[(unsuppressed) ](#FFA500)[(fix) ](#33BBC8)[NoDebug](#FF0000): Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       [^^^^^](#FF0000)

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum.

Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula.

                                                            [src/FileA.elm  ↑
====o======================================================================o====
    ↓  src/FileA.elm](#FF0000)


[-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5](#33BBC8)

[(fix) ](#33BBC8)[NoDebug2](#FF0000): Do not use Debug2

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       [^^^^^](#FF0000)

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum.

Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula.

[Errors marked with (fix) can be fixed automatically using `elm-review --fix`.](#33BBC8)

I found [2 errors](#FF0000) in [2 files](#E8C338)."""
                        }
        , test "report show suppressed warning when getting errors from suppressed rules that are not the unsuppressed ones" <|
            \() ->
                [ { path = Reporter.FilePath "src/FileA.elm"
                  , source = Reporter.Source """module FileA exposing (a)
a = Debug.log "debug" 1"""
                  , errors =
                        [ { ruleName = "NoDebug"
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
                          , providesFix = True
                          , fixProblem = Nothing
                          , providesFileRemovalFix = False
                          , suppressed = True
                          }
                        ]
                  }
                , { path = Reporter.FilePath "src/FileA.elm"
                  , source = Reporter.Source """module FileA exposing (a)
a = Debug.log "debug" 1"""
                  , errors =
                        [ { ruleName = "NoDebug2"
                          , ruleLink = Just "https://package.elm-lang.org/packages/author/package/1.0.0/NoDebug"
                          , message = "Do not use Debug2"
                          , details =
                                [ "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum."
                                , "Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula."
                                ]
                          , range =
                                { start = { row = 2, column = 5 }
                                , end = { row = 2, column = 10 }
                                }
                          , providesFix = True
                          , fixProblem = Nothing
                          , providesFileRemovalFix = False
                          , suppressed = False
                          }
                        ]
                  }
                ]
                    |> Reporter.formatReport
                        { suppressedErrors = SuppressedErrors.empty
                        , unsuppressMode = UnsuppressMode.UnsuppressRules (Set.singleton "OtherRule")

                        -- Note: the original number of suppressed errors and the list of those don't matter when errors are shown
                        , originalNumberOfSuppressedErrors = 0
                        , detailsMode = Reporter.WithDetails
                        , fixExplanation = FixExplanation.Succinct
                        , mode = Reporter.Reviewing
                        , errorsHaveBeenFixedPreviously = False
                        }
                    |> expect
                        { withoutColors = """-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5

(unsuppressed) (fix) NoDebug: Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       ^^^^^

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum.

Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula.

                                                            src/FileA.elm  ↑
====o======================================================================o====
    ↓  src/FileA.elm


-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5

(fix) NoDebug2: Do not use Debug2

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       ^^^^^

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum.

Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula.

Errors marked with (unsuppressed) were previously suppressed, but you introduced new errors for the same rule and file. There are now more of those than what I previously allowed. Please fix them until you have at most as many errors as before. Maybe fix a few more while you're there?

Errors marked with (fix) can be fixed automatically using `elm-review --fix`.

I found 2 errors in 2 files."""
                        , withColors = """[-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5](#33BBC8)

[(unsuppressed) ](#FFA500)[(fix) ](#33BBC8)[NoDebug](#FF0000): Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       [^^^^^](#FF0000)

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum.

Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula.

                                                            [src/FileA.elm  ↑
====o======================================================================o====
    ↓  src/FileA.elm](#FF0000)


[-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5](#33BBC8)

[(fix) ](#33BBC8)[NoDebug2](#FF0000): Do not use Debug2

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       [^^^^^](#FF0000)

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum.

Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula.

[Errors marked with (unsuppressed) were previously suppressed, but you introduced new errors for the same rule and file. There are now more of those than what I previously allowed. Please fix them until you have at most as many errors as before. Maybe fix a few more while you're there?](#FFA500)

[Errors marked with (fix) can be fixed automatically using `elm-review --fix`.](#33BBC8)

I found [2 errors](#FF0000) in [2 files](#E8C338)."""
                        }
        ]


unicodeTests : Test
unicodeTests =
    describe "Positioning of underline when encountering unicode characters "
        [ test "add underline at the correct position when unicode characters are in front of the underlined string" <|
            \() ->
                [ { path = Reporter.FilePath "src/FileA.elm"
                  , source = Reporter.Source """module FileA exposing (a)
a = "🔧" <| Debug.log "debug" 1"""
                  , errors =
                        [ { ruleName = "NoDebug"
                          , ruleLink = Just "https://package.elm-lang.org/packages/author/package/1.0.0/NoDebug"
                          , message = "Do not use Debug"
                          , details = [ "Some description." ]
                          , range =
                                { start = { row = 2, column = 12 }
                                , end = { row = 2, column = 17 }
                                }
                          , providesFix = False
                          , fixProblem = Nothing
                          , providesFileRemovalFix = False
                          , suppressed = False
                          }
                        ]
                  }
                ]
                    |> Reporter.formatReport
                        { suppressedErrors = SuppressedErrors.empty
                        , unsuppressMode = UnsuppressMode.UnsuppressNone
                        , originalNumberOfSuppressedErrors = 0
                        , detailsMode = Reporter.WithDetails
                        , fixExplanation = FixExplanation.Succinct
                        , mode = Reporter.Reviewing
                        , errorsHaveBeenFixedPreviously = False
                        }
                    |> expect
                        { withoutColors = """-- ELM-REVIEW ERROR ----------------------------------------- src/FileA.elm:2:12

NoDebug: Do not use Debug

1| module FileA exposing (a)
2| a = "🔧" <| Debug.log "debug" 1
               ^^^^^

Some description.

I found 1 error in 1 file."""
                        , withColors = """[-- ELM-REVIEW ERROR ----------------------------------------- src/FileA.elm:2:12](#33BBC8)

[NoDebug](#FF0000): Do not use Debug

1| module FileA exposing (a)
2| a = "🔧" <| Debug.log "debug" 1
               [^^^^^](#FF0000)

Some description.

I found [1 error](#FF0000) in [1 file](#E8C338)."""
                        }
        , test "add underline at the correct position when unicode characters are contained in the underlined string" <|
            \() ->
                [ { path = Reporter.FilePath "src/FileA.elm"
                  , source = Reporter.Source """module FileA exposing (a)
a = "🔧" ++ 1"""
                  , errors =
                        [ { ruleName = "NoDebug"
                          , ruleLink = Just "https://package.elm-lang.org/packages/author/package/1.0.0/NoDebug"
                          , message = "Do not use Debug"
                          , details = [ "Some description." ]
                          , range =
                                { start = { row = 2, column = 5 }
                                , end = { row = 2, column = 8 }
                                }
                          , providesFix = False
                          , fixProblem = Nothing
                          , providesFileRemovalFix = False
                          , suppressed = False
                          }
                        ]
                  }
                ]
                    |> Reporter.formatReport
                        { suppressedErrors = SuppressedErrors.empty
                        , unsuppressMode = UnsuppressMode.UnsuppressNone
                        , originalNumberOfSuppressedErrors = 0
                        , detailsMode = Reporter.WithDetails
                        , fixExplanation = FixExplanation.Succinct
                        , mode = Reporter.Reviewing
                        , errorsHaveBeenFixedPreviously = False
                        }
                    |> expect
                        { withoutColors = """-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5

NoDebug: Do not use Debug

1| module FileA exposing (a)
2| a = "🔧" ++ 1
       ^^^^

Some description.

I found 1 error in 1 file."""
                        , withColors = """[-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5](#33BBC8)

[NoDebug](#FF0000): Do not use Debug

1| module FileA exposing (a)
2| a = "🔧" ++ 1
       [^^^^](#FF0000)

Some description.

I found [1 error](#FF0000) in [1 file](#E8C338)."""
                        }
        , test "add underline at the correct position in multiline strings" <|
            \() ->
                [ { path = Reporter.FilePath "src/FileA.elm"
                  , source = Reporter.Source """module FileA exposing (a)
a = "🔧" ++ "🔧
    "🔧" ++ "🔧"
  yes" ++ 1"""
                  , errors =
                        [ { ruleName = "NoDebug"
                          , ruleLink = Just "https://package.elm-lang.org/packages/author/package/1.0.0/NoDebug"
                          , message = "Do not use Debug"
                          , details = [ "Some description." ]
                          , range =
                                { start = { row = 2, column = 12 }
                                , end = { row = 4, column = 7 }
                                }
                          , providesFix = False
                          , fixProblem = Nothing
                          , providesFileRemovalFix = False
                          , suppressed = False
                          }
                        ]
                  }
                ]
                    |> Reporter.formatReport
                        { suppressedErrors = SuppressedErrors.empty
                        , unsuppressMode = UnsuppressMode.UnsuppressNone
                        , originalNumberOfSuppressedErrors = 0
                        , detailsMode = Reporter.WithDetails
                        , fixExplanation = FixExplanation.Succinct
                        , mode = Reporter.Reviewing
                        , errorsHaveBeenFixedPreviously = False
                        }
                    |> expect
                        { withoutColors = """-- ELM-REVIEW ERROR ----------------------------------------- src/FileA.elm:2:12

NoDebug: Do not use Debug

1| module FileA exposing (a)
2| a = "🔧" ++ "🔧
               ^^^
3|     "🔧" ++ "🔧"
       ^^^^^^^^^^^^
4|   yes" ++ 1
     ^^^^

Some description.

I found 1 error in 1 file."""
                        , withColors = """[-- ELM-REVIEW ERROR ----------------------------------------- src/FileA.elm:2:12](#33BBC8)

[NoDebug](#FF0000): Do not use Debug

1| module FileA exposing (a)
2| a = "🔧" ++ "🔧
               [^^^](#FF0000)
3|     "🔧" ++ "🔧"
       [^^^^^^^^^^^^](#FF0000)
4|   yes" ++ 1
     [^^^^](#FF0000)

Some description.

I found [1 error](#FF0000) in [1 file](#E8C338)."""
                        }
        ]

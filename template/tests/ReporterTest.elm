module ReporterTest exposing (multipleErrorsIncludingGlobalErrorTest, suite)

import Elm.Review.Reporter as Reporter
import Elm.Review.SuppressedErrors as SuppressedErrors exposing (SuppressedErrors)
import Elm.Review.UnsuppressMode as UnsuppressMode
import FormatTester exposing (expect)
import Review.Fix
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
                      , fixFailure = Nothing
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
                      , fixFailure = Nothing
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
                      , fixFailure = Nothing
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
                          , fixFailure = Nothing
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
                          , fixFailure = Nothing
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
                          , fixFailure = Nothing
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
                          , fixFailure = Nothing
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
                          , fixFailure = Nothing
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
                          , details =
                                [ "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum."
                                , "Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula."
                                ]
                          , range =
                                { start = { row = 2, column = 5 }
                                , end = { row = 2, column = 10 }
                                }
                          , providesFix = True
                          , fixFailure = Nothing
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
                        , mode = Reporter.Reviewing
                        , errorsHaveBeenFixedPreviously = False
                        }
                    |> expect
                        { withoutColors = """-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5

(fix) NoDebug: Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       ^^^^^

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum.

Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula.

Errors marked with (fix) can be fixed automatically using `elm-review --fix`.

I found 1 error in 1 file."""
                        , withColors = """[-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5](#33BBC8)

[(fix) ](#33BBC8)[NoDebug](#FF0000): Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       [^^^^^](#FF0000)

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum.

Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula.

[Errors marked with (fix) can be fixed automatically using `elm-review --fix`.](#33BBC8)

I found [1 error](#FF0000) in [1 file](#E8C338)."""
                        }
        , test "should mention a fix is failing when the error provides one in fix mode" <|
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
                          , fixFailure = Just Review.Fix.HasCollisionsInFixRanges
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
                        , mode = Reporter.Fixing
                        , errorsHaveBeenFixedPreviously = False
                        }
                    |> expect
                        { withoutColors = """-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5

(FIX FAILED) NoDebug: Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       ^^^^^

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum.

Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula.

I failed to apply the automatic fix because it was invalid.

I tried applying some fixes but they failed in ways the author(s) didn't expect. Please let the author(s) of the following rules know:
- NoDebug

I found 1 error in 1 file."""
                        , withColors = """[-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5](#33BBC8)

[(FIX FAILED) ](#E8C338)[NoDebug](#FF0000): Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       [^^^^^](#FF0000)

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum.

Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula.

[I failed to apply the automatic fix because it was invalid.](#E8C338)

[I tried applying some fixes but they failed in ways the author(s) didn't expect. Please let the author(s) of the following rules know:
- NoDebug](#E8C338)

I found [1 error](#FF0000) in [1 file](#E8C338)."""
                        }
        , test "should not mention an error is fixable when the fix fails in review mode" <|
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
                          , fixFailure = Just Review.Fix.HasCollisionsInFixRanges
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
                      , fixFailure = Nothing
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
                      , fixFailure = Nothing
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
                      , fixFailure = Nothing
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
                          , details =
                                [ "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum."
                                , "Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula."
                                ]
                          , range =
                                { start = { row = 2, column = 5 }
                                , end = { row = 2, column = 10 }
                                }
                          , providesFix = True
                          , fixFailure = Nothing
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

Errors marked with (unsuppressed) were previously suppressed, but you introduced new errors for the same rule and file. There are now more of those than what I previously allowed. Please fix them until you have at most as many errors as before. Maybe fix a few more while you're there?

Errors marked with (fix) can be fixed automatically using `elm-review --fix`.

I found 1 error in 1 file."""
                        , withColors = """[-- ELM-REVIEW ERROR ------------------------------------------ src/FileA.elm:2:5](#33BBC8)

[(unsuppressed) ](#FFA500)[(fix) ](#33BBC8)[NoDebug](#FF0000): Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
       [^^^^^](#FF0000)

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum cursus erat ullamcorper, commodo leo quis, sollicitudin eros. Sed semper mattis ex, vitae dignissim lectus. Integer eu risus augue. Nam egestas lacus non lacus molestie mattis. Phasellus magna dui, ultrices eu massa nec, interdum tincidunt eros. Aenean rutrum a purus nec cursus. Integer ullamcorper leo non lectus dictum, in vulputate justo vulputate. Donec ullamcorper finibus quam sed dictum.

Donec sed ligula ac mi pretium mattis et in nisi. Nulla nec ex hendrerit, sollicitudin eros at, mattis tortor. Ut lacinia ornare lectus in vestibulum. Nam congue ultricies dolor, in venenatis nulla sagittis nec. In ac leo sit amet diam iaculis ornare eu non odio. Proin sed orci et urna tincidunt tincidunt quis a lacus. Donec euismod odio nulla, sit amet iaculis lorem interdum sollicitudin. Vivamus bibendum quam urna, in tristique lacus iaculis id. In tempor lectus ipsum, vehicula bibendum magna pretium vitae. Cras ullamcorper rutrum nunc non sollicitudin. Curabitur tempus eleifend nunc, sed ornare nisl tincidunt vel. Maecenas eu nisl ligula.

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
                          , fixFailure = Nothing
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
                          , fixFailure = Nothing
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
                          , fixFailure = Nothing
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
                          , fixFailure = Nothing
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
                          , fixFailure = Nothing
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
                          , fixFailure = Nothing
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
                          , fixFailure = Nothing
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
                          , fixFailure = Nothing
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
                          , fixFailure = Nothing
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

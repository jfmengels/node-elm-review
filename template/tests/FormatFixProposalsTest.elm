module FormatFixProposalsTest exposing (suite)

import Dict
import Elm.Review.Reporter as Reporter exposing (Error)
import FormatTester exposing (expect)
import Review.Project as Project
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "formatFixProposals"
        [ test "propose fix for a single file and error" <|
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
                        , providesFix = True
                        , fixFailure = Nothing
                        , providesFileRemovalFix = False
                        , suppressed = False
                        }
                in
                Reporter.formatFixProposals
                    True
                    (Dict.fromList [ ( "src/FileA.elm", [ error ] ) ])
                    [ { path = "src/FileA.elm"
                      , diff =
                            Project.Edited
                                { before = """module FileA exposing (a)
a = Debug.log "debug" 1
other=lines
other2=lines2
"""
                                , after = """module FileA exposing (a)
a = 1
other=lines
other2=lines2
"""
                                }
                      }
                    ]
                    |> expect
                        { withoutColors = """-- ELM-REVIEW FIX-ALL PROPOSAL -------------------------------------------------

I found fixable errors for the following files:
  - src/FileA.elm

Here is how the code would change if you applied each fix.

------------------------------------------------------------------ src/FileA.elm

Modified by the following error fixes:
NoDebug: Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
+| a = 1
3| other=lines
"""
                        , withColors = """[-- ELM-REVIEW FIX-ALL PROPOSAL -------------------------------------------------](#33BBC8)

I found fixable errors for the following files:
  [- src/FileA.elm](#E8C338)

Here is how the code would change if you applied each fix.

[------------------------------------------------------------------ src/FileA.elm](#33BBC8)

Modified by the following error fixes:
[NoDebug](#FF0000): Do not use Debug

1| module FileA exposing (a)
[2| a = Debug.log "debug" 1](#FF0000)
[+| a = 1](#008000)
3| other=lines
"""
                        }
        , test "propose fix for multiple changed files" <|
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
                        , providesFix = True
                        , fixFailure = Nothing
                        , providesFileRemovalFix = False
                        , suppressed = False
                        }
                in
                Reporter.formatFixProposals
                    True
                    (Dict.fromList
                        [ ( "src/FileA.elm", [ error ] )
                        , ( "src/FileB.elm", [ error ] )
                        ]
                    )
                    [ { path = "src/FileA.elm"
                      , diff =
                            Project.Edited
                                { before = """module FileA exposing (a)
a = Debug.log "debug" 1
other=lines
other2=lines2
"""
                                , after = """module FileA exposing (a)
a = 1
other=lines
other2=lines2
"""
                                }
                      }
                    , { path = "src/FileB.elm"
                      , diff =
                            Project.Edited
                                { before = """module FileB exposing (b)
b = Debug.log "debug" someOther
someOther=lines
"""
                                , after = """module FileB exposing (b)
b = someOther
someOther=lines
"""
                                }
                      }
                    ]
                    |> expect
                        { withoutColors = """-- ELM-REVIEW FIX-ALL PROPOSAL -------------------------------------------------

I found fixable errors for the following files:
  - src/FileA.elm
  - src/FileB.elm

Here is how the code would change if you applied each fix.

------------------------------------------------------------------ src/FileA.elm

Modified by the following error fixes:
NoDebug: Do not use Debug

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
+| a = 1
3| other=lines


                                                            src/FileA.elm  ↑
====o======================================================================o====
    ↓  src/FileB.elm


------------------------------------------------------------------ src/FileB.elm

Modified by the following error fixes:
NoDebug: Do not use Debug

1| module FileB exposing (b)
2| b = Debug.log "debug" someOther
+| b = someOther
3| someOther=lines
"""
                        , withColors = """[-- ELM-REVIEW FIX-ALL PROPOSAL -------------------------------------------------](#33BBC8)

I found fixable errors for the following files:
  [- src/FileA.elm](#E8C338)
  [- src/FileB.elm](#E8C338)

Here is how the code would change if you applied each fix.

[------------------------------------------------------------------ src/FileA.elm](#33BBC8)

Modified by the following error fixes:
[NoDebug](#FF0000): Do not use Debug

1| module FileA exposing (a)
[2| a = Debug.log "debug" 1](#FF0000)
[+| a = 1](#008000)
3| other=lines


                                                            [src/FileA.elm  ↑
====o======================================================================o====
    ↓  src/FileB.elm](#FF0000)


[------------------------------------------------------------------ src/FileB.elm](#33BBC8)

Modified by the following error fixes:
[NoDebug](#FF0000): Do not use Debug

1| module FileB exposing (b)
[2| b = Debug.log "debug" someOther](#FF0000)
[+| b = someOther](#008000)
3| someOther=lines
"""
                        }
        , test "propose fix for multiple deleted files" <|
            \() ->
                let
                    error : Error
                    error =
                        { ruleName = "NoDebug"
                        , ruleLink = Just "https://package.elm-lang.org/packages/author/package/1.0.0/NoDebug"
                        , message = "Unused module"
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
                        , providesFileRemovalFix = False
                        , suppressed = False
                        }
                in
                Reporter.formatFixProposals
                    True
                    (Dict.fromList
                        [ ( "src/FileA.elm", [ error ] )
                        , ( "src/FileB.elm", [ error ] )
                        ]
                    )
                    [ { path = "src/FileA.elm"
                      , diff = Project.Removed
                      }
                    , { path = "src/FileB.elm"
                      , diff = Project.Removed
                      }
                    ]
                    |> expect
                        { withoutColors = """-- ELM-REVIEW FIX-ALL PROPOSAL -------------------------------------------------

I found fixable errors for the following files:
  - src/FileA.elm
  - src/FileB.elm

Here is how the code would change if you applied each fix.

------------------------------------------------------------------ src/FileA.elm

Modified by the following error fixes:
NoDebug: Unused module

    REMOVE FILE


                                                            src/FileA.elm  ↑
====o======================================================================o====
    ↓  src/FileB.elm


------------------------------------------------------------------ src/FileB.elm

Modified by the following error fixes:
NoDebug: Unused module

    REMOVE FILE
"""
                        , withColors = """[-- ELM-REVIEW FIX-ALL PROPOSAL -------------------------------------------------](#33BBC8)

I found fixable errors for the following files:
  [- src/FileA.elm](#E8C338)
  [- src/FileB.elm](#E8C338)

Here is how the code would change if you applied each fix.

[------------------------------------------------------------------ src/FileA.elm](#33BBC8)

Modified by the following error fixes:
[NoDebug](#FF0000): Unused module

[    REMOVE FILE](#FF0000)


                                                            [src/FileA.elm  ↑
====o======================================================================o====
    ↓  src/FileB.elm](#FF0000)


[------------------------------------------------------------------ src/FileB.elm](#33BBC8)

Modified by the following error fixes:
[NoDebug](#FF0000): Unused module

[    REMOVE FILE](#FF0000)
"""
                        }
        , test "propose fix for multiple edited and deleted files" <|
            \() ->
                let
                    error : Error
                    error =
                        { ruleName = "NoDebug"
                        , ruleLink = Just "https://package.elm-lang.org/packages/author/package/1.0.0/NoDebug"
                        , message = "Unused module"
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
                        , providesFileRemovalFix = False
                        , suppressed = False
                        }
                in
                Reporter.formatFixProposals
                    True
                    (Dict.fromList
                        [ ( "src/FileA.elm", [ error ] )
                        , ( "src/FileB.elm", [ error ] )
                        , ( "src/FileC.elm", [ error ] )
                        , ( "src/FileD.elm", [ error ] )
                        ]
                    )
                    [ { path = "src/FileA.elm"
                      , diff =
                            Project.Edited
                                { before = """module FileA exposing (a)
a = Debug.log "debug" 1
other=lines
other2=lines2
"""
                                , after = """module FileA exposing (a)
a = 1
other=lines
other2=lines2
"""
                                }
                      }
                    , { path = "src/FileB.elm"
                      , diff = Project.Removed
                      }
                    , { path = "src/FileC.elm"
                      , diff =
                            Project.Edited
                                { before = """module FileC exposing (b)
b = Debug.log "debug" someOther
someOther=lines
"""
                                , after = """module FileC exposing (b)
b = someOther
someOther=lines
"""
                                }
                      }
                    , { path = "src/FileD.elm"
                      , diff = Project.Removed
                      }
                    ]
                    |> expect
                        { withoutColors = """-- ELM-REVIEW FIX-ALL PROPOSAL -------------------------------------------------

I found fixable errors for the following files:
  - src/FileA.elm
  - src/FileC.elm
  - src/FileB.elm
  - src/FileD.elm

Here is how the code would change if you applied each fix.

------------------------------------------------------------------ src/FileA.elm

Modified by the following error fixes:
NoDebug: Unused module

1| module FileA exposing (a)
2| a = Debug.log "debug" 1
+| a = 1
3| other=lines


                                                            src/FileA.elm  ↑
====o======================================================================o====
    ↓  src/FileC.elm


------------------------------------------------------------------ src/FileC.elm

Modified by the following error fixes:
NoDebug: Unused module

1| module FileC exposing (b)
2| b = Debug.log "debug" someOther
+| b = someOther
3| someOther=lines


                                                            src/FileC.elm  ↑
====o======================================================================o====
    ↓  src/FileB.elm


------------------------------------------------------------------ src/FileB.elm

Modified by the following error fixes:
NoDebug: Unused module

    REMOVE FILE


                                                            src/FileB.elm  ↑
====o======================================================================o====
    ↓  src/FileD.elm


------------------------------------------------------------------ src/FileD.elm

Modified by the following error fixes:
NoDebug: Unused module

    REMOVE FILE
"""
                        , withColors = """[-- ELM-REVIEW FIX-ALL PROPOSAL -------------------------------------------------](#33BBC8)

I found fixable errors for the following files:
  [- src/FileA.elm](#E8C338)
  [- src/FileC.elm](#E8C338)
  [- src/FileB.elm](#E8C338)
  [- src/FileD.elm](#E8C338)

Here is how the code would change if you applied each fix.

[------------------------------------------------------------------ src/FileA.elm](#33BBC8)

Modified by the following error fixes:
[NoDebug](#FF0000): Unused module

1| module FileA exposing (a)
[2| a = Debug.log "debug" 1](#FF0000)
[+| a = 1](#008000)
3| other=lines


                                                            [src/FileA.elm  ↑
====o======================================================================o====
    ↓  src/FileC.elm](#FF0000)


[------------------------------------------------------------------ src/FileC.elm](#33BBC8)

Modified by the following error fixes:
[NoDebug](#FF0000): Unused module

1| module FileC exposing (b)
[2| b = Debug.log "debug" someOther](#FF0000)
[+| b = someOther](#008000)
3| someOther=lines


                                                            [src/FileC.elm  ↑
====o======================================================================o====
    ↓  src/FileB.elm](#FF0000)


[------------------------------------------------------------------ src/FileB.elm](#33BBC8)

Modified by the following error fixes:
[NoDebug](#FF0000): Unused module

[    REMOVE FILE](#FF0000)


                                                            [src/FileB.elm  ↑
====o======================================================================o====
    ↓  src/FileD.elm](#FF0000)


[------------------------------------------------------------------ src/FileD.elm](#33BBC8)

Modified by the following error fixes:
[NoDebug](#FF0000): Unused module

[    REMOVE FILE](#FF0000)
"""
                        }
        ]

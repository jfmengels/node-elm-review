module FormatFixProposalTest exposing (suite)

import Elm.Review.Reporter as Reporter exposing (Error, File)
import FormatTester exposing (expect)
import Review.Project as Project
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
                        , providesFix = True
                        , fixFailure = Nothing
                        , missingFileRemovalFlag = False
                        , suppressed = False
                        }

                    fileBefore : String
                    fileBefore =
                        """module FileA exposing (a)
a = Debug.log "debug" 1
other=lines
other2=lines2

some =
  dummy
    a
    a
    a
    a
    a
    a
    a
    a
    a
"""

                    fileAfter : String
                    fileAfter =
                        """module FileA exposing (a)
a = 1
other=lines
other2=lines2

some =
  dummy
    a
    a
    a
    a
    a
    a
    a
    a
    a
"""

                    path : String
                    path =
                        "src/FileA.elm"

                    file : File
                    file =
                        { path = Reporter.FilePath path
                        , source = Reporter.Source fileBefore
                        }
                in
                Reporter.formatSingleFixProposal Reporter.WithDetails
                    file
                    error
                    [ { path = path
                      , diff = Project.Edited { before = fileBefore, after = fileAfter }
                      }
                    ]
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
+| a = 1
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
[+| a = 1](#008000)
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
                        , providesFix = True
                        , fixFailure = Nothing
                        , missingFileRemovalFlag = False
                        , suppressed = False
                        }

                    file : File
                    file =
                        { path = Reporter.FilePath path
                        , source = Reporter.Source fileBefore
                        }

                    path : String
                    path =
                        "src/Some/File.elm"

                    fileBefore : String
                    fileBefore =
                        """module Some.File exposing (a)
a =
    1

b =
    a
"""

                    fixedSource : String
                    fixedSource =
                        """module Some.File exposing (a)


b =
    a
"""
                in
                Reporter.formatSingleFixProposal Reporter.WithDetails
                    file
                    error
                    [ { path = path
                      , diff = Project.Edited { before = fileBefore, after = fixedSource }
                      }
                    ]
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
4|
+|
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
4|
[+|](#008000)
5| b =
"""
                        }
        , test "propose fix where the diff is for the first line, followed by a blank line" <|
            \() ->
                let
                    error : Error
                    error =
                        { ruleName = "Some.Rule.Name"
                        , ruleLink = Just "https://package.elm-lang.org/packages/author/package/1.0.0/Some-Rule-Name"
                        , message = "Some message"
                        , details = [ "Some details" ]
                        , range =
                            { start = { row = 1, column = 1 }
                            , end = { row = 1, column = 2 }
                            }
                        , providesFix = True
                        , fixFailure = Nothing
                        , missingFileRemovalFlag = False
                        , suppressed = False
                        }

                    file : File
                    file =
                        { path = Reporter.FilePath path
                        , source = Reporter.Source fileBefore
                        }

                    path : String
                    path =
                        "src/Some/File.elm"

                    fileBefore : String
                    fileBefore =
                        """module Some.File exposing (..)

a =
    1
"""

                    fixedSource : String
                    fixedSource =
                        """module Some.File exposing (a)

a =
    1
"""
                in
                Reporter.formatSingleFixProposal Reporter.WithDetails
                    file
                    error
                    [ { path = path
                      , diff = Project.Edited { before = fileBefore, after = fixedSource }
                      }
                    ]
                    |> expect
                        { withoutColors =
                            """-- ELM-REVIEW ERROR -------------------------------------- src/Some/File.elm:1:1

Some.Rule.Name: Some message

1| module Some.File exposing (..)
   ^

Some details

I think I can fix this. Here is my proposal:

1| module Some.File exposing (..)
+| module Some.File exposing (a)
2|
"""
                        , withColors =
                            """[-- ELM-REVIEW ERROR -------------------------------------- src/Some/File.elm:1:1](#33BBC8)

[Some.Rule.Name](#FF0000): Some message

1| module Some.File exposing (..)
   [^](#FF0000)

Some details

[I think I can fix this. Here is my proposal:](#33BBC8)

[1| module Some.File exposing (..)](#FF0000)
[+| module Some.File exposing (a)](#008000)
2|
"""
                        }
        , test "propose fix with a removed file" <|
            \() ->
                let
                    error : Error
                    error =
                        { ruleName = "Some.Rule.Name"
                        , ruleLink = Just "https://package.elm-lang.org/packages/author/package/1.0.0/Some-Rule-Name"
                        , message = "Some message"
                        , details = [ "Some details" ]
                        , range =
                            { start = { row = 1, column = 7 }
                            , end = { row = 1, column = 16 }
                            }
                        , providesFix = True
                        , fixFailure = Nothing
                        , missingFileRemovalFlag = False
                        , suppressed = False
                        }

                    path : String
                    path =
                        "src/Some/File.elm"

                    fileBefore : String
                    fileBefore =
                        """module Some.File exposing (a)
a =
    1

b =
    a
"""

                    file : File
                    file =
                        { path = Reporter.FilePath path
                        , source = Reporter.Source fileBefore
                        }
                in
                Reporter.formatSingleFixProposal Reporter.WithDetails
                    file
                    error
                    [ { path = path
                      , diff = Project.Removed
                      }
                    ]
                    |> expect
                        { withoutColors =
                            """-- ELM-REVIEW ERROR -------------------------------------- src/Some/File.elm:1:7

Some.Rule.Name: Some message

1| module Some.File exposing (a)
         ^^^^^^^^^
2| a =

Some details

I think I can fix this. Here is my proposal:

    REMOVE FILE src/Some/File.elm
"""
                        , withColors =
                            """[-- ELM-REVIEW ERROR -------------------------------------- src/Some/File.elm:1:7](#33BBC8)

[Some.Rule.Name](#FF0000): Some message

1| module Some.File exposing (a)
         [^^^^^^^^^](#FF0000)
2| a =

Some details

[I think I can fix this. Here is my proposal:](#33BBC8)

[    REMOVE FILE src/Some/File.elm](#FF0000)
"""
                        }
        , test "propose fix with multiple removed files" <|
            \() ->
                let
                    error : Error
                    error =
                        { ruleName = "Some.Rule.Name"
                        , ruleLink = Just "https://package.elm-lang.org/packages/author/package/1.0.0/Some-Rule-Name"
                        , message = "Some message"
                        , details = [ "Some details" ]
                        , range =
                            { start = { row = 1, column = 7 }
                            , end = { row = 1, column = 16 }
                            }
                        , providesFix = True
                        , fixFailure = Nothing
                        , missingFileRemovalFlag = False
                        , suppressed = False
                        }

                    path : String
                    path =
                        "src/Some/File.elm"

                    fileBefore : String
                    fileBefore =
                        """module Some.File exposing (a)
a =
    1

b =
    a
"""

                    file : File
                    file =
                        { path = Reporter.FilePath path
                        , source = Reporter.Source fileBefore
                        }
                in
                Reporter.formatSingleFixProposal Reporter.WithDetails
                    file
                    error
                    [ { path = path
                      , diff = Project.Removed
                      }
                    , { path = "src/Some/Other/File.elm"
                      , diff = Project.Removed
                      }
                    ]
                    |> expect
                        { withoutColors =
                            """-- ELM-REVIEW ERROR -------------------------------------- src/Some/File.elm:1:7

Some.Rule.Name: Some message

1| module Some.File exposing (a)
         ^^^^^^^^^
2| a =

Some details

I think I can fix this. Here is my proposal:

1/2 ---------------------------------------------------------- src/Some/File.elm

    REMOVE FILE

2/2 ---------------------------------------------------- src/Some/Other/File.elm

    REMOVE FILE
"""
                        , withColors =
                            """[-- ELM-REVIEW ERROR -------------------------------------- src/Some/File.elm:1:7](#33BBC8)

[Some.Rule.Name](#FF0000): Some message

1| module Some.File exposing (a)
         [^^^^^^^^^](#FF0000)
2| a =

Some details

[I think I can fix this. Here is my proposal:](#33BBC8)

[1/2 ---------------------------------------------------------- src/Some/File.elm](#33BBC8)

[    REMOVE FILE](#FF0000)

[2/2 ---------------------------------------------------- src/Some/Other/File.elm](#33BBC8)

[    REMOVE FILE](#FF0000)
"""
                        }
        , test "propose fix with multiple file edits and file removals" <|
            \() ->
                let
                    error : Error
                    error =
                        { ruleName = "Some.Rule.Name"
                        , ruleLink = Just "https://package.elm-lang.org/packages/author/package/1.0.0/Some-Rule-Name"
                        , message = "Some message"
                        , details = [ "Some details" ]
                        , range =
                            { start = { row = 1, column = 7 }
                            , end = { row = 1, column = 16 }
                            }
                        , providesFix = True
                        , fixFailure = Nothing
                        , missingFileRemovalFlag = False
                        , suppressed = False
                        }

                    path : String
                    path =
                        "src/Some/File.elm"

                    fileBefore : String
                    fileBefore =
                        """module Some.File exposing (a)
a =
    1

b =
    a
"""

                    fixedSource : String
                    fixedSource =
                        """module Some.File exposing (a)


b =
    a
"""

                    file : File
                    file =
                        { path = Reporter.FilePath path
                        , source = Reporter.Source fileBefore
                        }
                in
                Reporter.formatSingleFixProposal Reporter.WithDetails
                    file
                    error
                    [ { path = path
                      , diff = Project.Edited { before = fileBefore, after = fixedSource }
                      }
                    , { path = path
                      , diff = Project.Removed
                      }
                    , { path = "src/Some/Other/File.elm"
                      , diff = Project.Removed
                      }
                    ]
                    |> expect
                        { withoutColors =
                            """-- ELM-REVIEW ERROR -------------------------------------- src/Some/File.elm:1:7

Some.Rule.Name: Some message

1| module Some.File exposing (a)
         ^^^^^^^^^
2| a =

Some details

I think I can fix this. Here is my proposal:

1/3 ---------------------------------------------------------- src/Some/File.elm

1| module Some.File exposing (a)
2| a =
3|     1
4|
+|
5| b =

2/3 ---------------------------------------------------------- src/Some/File.elm

    REMOVE FILE

3/3 ---------------------------------------------------- src/Some/Other/File.elm

    REMOVE FILE
"""
                        , withColors =
                            """[-- ELM-REVIEW ERROR -------------------------------------- src/Some/File.elm:1:7](#33BBC8)

[Some.Rule.Name](#FF0000): Some message

1| module Some.File exposing (a)
         [^^^^^^^^^](#FF0000)
2| a =

Some details

[I think I can fix this. Here is my proposal:](#33BBC8)

[1/3 ---------------------------------------------------------- src/Some/File.elm](#33BBC8)

1| module Some.File exposing (a)
[2| a =](#FF0000)
[3|     1](#FF0000)
4|
[+|](#008000)
5| b =

[2/3 ---------------------------------------------------------- src/Some/File.elm](#33BBC8)

[    REMOVE FILE](#FF0000)

[3/3 ---------------------------------------------------- src/Some/Other/File.elm](#33BBC8)

[    REMOVE FILE](#FF0000)
"""
                        }
        ]

module Wrapper.FetchRemoteTemplate exposing (checkoutGitRepository)

{-|

@docs checkoutGitRepository

-}

import Elm.Review.Testable.Fs as Fs
import Elm.Review.Testable.Internal exposing (TTask)
import Elm.Review.Testable.Process as Process
import Elm.Review.Testable.ProcessData as ProcessData
import Elm.Review.Testable.TTask as TTask
import ElmReview.Color exposing (Color(..), Colorize)
import ElmReview.Path as Path exposing (Path)
import ElmReview.Problem as Problem exposing (Problem)
import ElmRun.ProcessExtra as ProcessExtra
import Wrapper.RemoteTemplate exposing (RemoteTemplate)


checkoutGitRepository : Bool -> RemoteTemplate -> Bool -> TTask Problem Path
checkoutGitRepository offline remoteTemplate debug =
    let
        repoFolder : Path
        repoFolder =
            Path.join
                [ -- TODO Use HOME and/or XDG_CACHE_HOME
                  "/Users/m1/.cache/elm-review/templates"
                , remoteTemplate.repoName
                ]

        git : List String -> TTask String ()
        git args =
            Process.run
                "git"
                { args = args
                , cwd = Just repoFolder
                , env = Nothing
                , stdin = ProcessData.NullStdin
                , stdout = ProcessData.stdoutSpec debug
                , stderr = ProcessData.CaptureStderr { maxBytes = 1024, onOverflow = ProcessData.TruncateOutput }
                }
                |> TTask.mapError (\error -> fromGitError args error)
                |> TTask.map (\_ -> ())

        {- Same as the `git` function but captures and returns the stdout output. -}
        gitCapture : List String -> TTask String String
        gitCapture args =
            Process.run
                "git"
                { args = args
                , cwd = Just repoFolder
                , env = Nothing
                , stdin = ProcessData.NullStdin
                , stdout = ProcessData.CaptureStdout { maxBytes = 1024, onOverflow = ProcessData.TruncateOutput }
                , stderr = ProcessData.CaptureStderr { maxBytes = 1024, onOverflow = ProcessData.TruncateOutput }
                }
                |> TTask.mapError (\error -> fromGitError args error)
                |> TTask.map (\result -> Maybe.withDefault "" result.stdout)
    in
    TTask.map2 (\() () -> Path.join2 repoFolder (Maybe.withDefault "." remoteTemplate.pathToFolder))
        (createRepoIfNecessary git offline remoteTemplate repoFolder)
        (pullAndCheckout { git = git, gitCapture = gitCapture } offline remoteTemplate)


fromGitError : List String -> ProcessData.SpawnError -> String
fromGitError args error =
    let
        errorDetails : String
        errorDetails =
            case error of
                ProcessData.ProcessRunError processError ->
                    ProcessData.errorToString processError

                ProcessData.CommandNotFound ->
                    "Command `git` not found"

                ProcessData.CommandFailed completed ->
                    Maybe.withDefault "No Git output." completed.stderr
    in
    "$ git " ++ String.join " " args ++ "\n\n" ++ errorDetails


createRepoIfNecessary : (List String -> TTask String ()) -> Bool -> RemoteTemplate -> Path -> TTask Problem ()
createRepoIfNecessary git offline remoteTemplate repoFolder =
    Fs.stat (Path.join2 repoFolder ".git")
        |> TTask.toResultTask
        |> TTask.andThen
            (\stat ->
                case stat of
                    Ok _ ->
                        TTask.succeed ()

                    Err _ ->
                        -- First time checkout out the repo, let's create it
                        if offline then
                            { title = "BRANCH OR COMMIT NOT FOUND"
                            , message = \c -> "You requested to run with the template at the " ++ c Yellow remoteTemplate.repoName ++ " but this is the first time using it. I therefore require network access, but you requested to run " ++ c Cyan "--offline" ++ """.
                            
Please acquire network access and re-run without """ ++ c Cyan "--offline" ++ ", or select another configuration to use."
                            }
                                |> Problem.from Problem.Unrecoverable
                                |> TTask.fail

                        else
                            createRepo git remoteTemplate repoFolder
            )


createRepo : (List String -> TTask String ()) -> RemoteTemplate -> Path -> TTask Problem ()
createRepo git remoteTemplate repoFolder =
    let
        repository : String
        repository =
            "git@github.com:" ++ remoteTemplate.repoName ++ ".git"
    in
    TTask.sequence
        [ Fs.createDirectory repoFolder
            |> TTask.onError (\_ -> TTask.succeed ())
        , git [ "init" ]

        -- TODO Support sparse-checkout to check out less files
        -- , git [ "sparse-checkout", "set", "--no-cone", "'!/*'", "'**/*.elm'", "'**/elm.json'", "'!**/tests/**/*.elm'" ]
        , git [ "remote", "add", "origin", repository ]
        ]
        |> TTask.mapError (\error -> Problem.unexpectedError "while checking out the template" error)


nextIndex : String -> String -> Maybe Int
nextIndex needle string =
    String.indexes needle string |> List.head


type alias Git =
    { git : List String -> TTask String ()
    , gitCapture : List String -> TTask String String
    }


pullAndCheckout : Git -> Bool -> RemoteTemplate -> TTask Problem ()
pullAndCheckout { git, gitCapture } offline remoteTemplate =
    if offline then
        getDefaultBranchFromLocalInformation gitCapture
            |> TTask.andThen (\reference -> switchToBranch git reference)

    else
        remoteTemplate.reference
            |> TTask.otherwise (\() -> findRemoteDefaultBranch gitCapture remoteTemplate)
            |> TTask.andThen
                (\reference ->
                    TTask.map2 (\() () -> ())
                        (fetchGitReference git reference remoteTemplate)
                        (switchToBranch git reference)
                )


switchToBranch : (List String -> TTask String ()) -> String -> TTask Problem ()
switchToBranch git reference =
    git [ "switch", "--discard-changes", reference ]
        |> TTask.mapError (\error -> Problem.unexpectedError "while checking out the template's code" error)


fetchGitReference : (List String -> TTask String ()) -> String -> RemoteTemplate -> TTask Problem ()
fetchGitReference git reference remoteTemplate =
    git [ "fetch", "origin", reference, "--depth=1" ]
        |> TTask.mapError
            (\error ->
                let
                    searchableError : String
                    searchableError =
                        String.toLower error
                in
                if String.contains "repository not found" searchableError then
                    { title = "REPOSITORY NOT FOUND"
                    , message = \c -> "I could not find the " ++ c Yellow remoteTemplate.repoName ++ """ repository.

Check the spelling and make sure it is a public repository, as I can't work with private ones at the moment."""
                    }
                        |> Problem.from Problem.Unrecoverable

                else if String.contains "couldn't find remote ref" searchableError then
                    { title = "BRANCH OR COMMIT NOT FOUND"
                    , message = \c -> "I found the " ++ c Yellow remoteTemplate.repoName ++ " repository, but I could not find the branch or commit " ++ c Yellow reference ++ """.

Please check the spelling and make sure it has been pushed."""
                    }
                        |> Problem.from Problem.Unrecoverable

                else
                    Problem.unexpectedError ("while fetching the contents of " ++ reference ++ " in the template") error
            )


findRemoteDefaultBranch : (List String -> TTask String String) -> RemoteTemplate -> TTask Problem String
findRemoteDefaultBranch gitCapture remoteTemplate =
    gitCapture [ "remote", "show", "origin" ]
        |> TTask.onError
            (\error ->
                if String.contains "repository not found" (String.toLower error) then
                    { title = "REPOSITORY NOT FOUND"
                    , message = \c -> "I could not find the " ++ c Yellow remoteTemplate.repoName ++ """ repository.

Check the spelling and make sure it is a public repository, as I can't work with private ones at the moment."""
                    }
                        |> Problem.from Problem.Unrecoverable
                        |> TTask.fail

                else
                    getDefaultBranchFromLocalInformation gitCapture
                        |> TTask.mapError (\_ -> Problem.unexpectedError "while trying to figure out the remote template's default Git branch" error)
            )
        |> TTask.andThen (\output -> headBranchName output |> TTask.fromResult)


getDefaultBranchFromLocalInformation : (List String -> TTask String String) -> TTask Problem String
getDefaultBranchFromLocalInformation gitCapture =
    gitCapture [ "symbolic-ref", "--short", "refs/remotes/origin/HEAD" ]
        |> TTask.mapError
            (\error ->
                Problem.unexpectedError "while trying to figure out the remote template's default Git branch offline" error
            )
        -- Output is "origin/<branchname>\n"
        |> TTask.map (\output -> String.dropLeft 7 (String.trim output))


headBranchName : String -> Result Problem String
headBranchName output =
    let
        searchTarget : String
        searchTarget =
            "HEAD branch: "

        maybeBranchName : Maybe String
        maybeBranchName =
            nextIndex searchTarget output
                |> Maybe.andThen
                    (\index ->
                        let
                            str : String
                            str =
                                output |> String.dropLeft (index + String.length searchTarget)
                        in
                        nextIndex "\n" str
                            |> Maybe.map (\endIndex -> String.left endIndex str)
                    )
    in
    case maybeBranchName of
        Just branchName ->
            Ok branchName

        Nothing ->
            { title = "COULD NOT FIGURE DEFAULT BRANCH FOR REMOTE"
            , message = \c -> headBranchNotFoundError searchTarget output c
            }
                |> Problem.from Problem.Unrecoverable
                |> Err


headBranchNotFoundError : String -> String -> Colorize -> String
headBranchNotFoundError searchTarget output c =
    "Since you did not specify a branch or commit when using " ++ c Cyan "--template" ++ """, I am trying to figure that out. In doing so, I used Git to figure that information and got a response.
            
I was looking for a line containing the string '""" ++ c Yellow searchTarget ++ """' but could not find it. Here is the full response:

""" ++ output

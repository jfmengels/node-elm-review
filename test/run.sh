#!/bin/bash

set -e

CWD=$(pwd)
CMD="elm-review"
TMP="$CWD/temporary"
SNAPSHOTS="$CWD/snapshots"
SUBCOMMAND="$1"
REPLACE_SCRIPT="node $CWD/replace-local-path.js"

# If you get errors like rate limit exceeded, you can run these tests
# with "GITHUB-AUTH=gitHubUserName:token"
# Follow this guide: https://docs.github.com/en/github/authenticating-to-github/creating-a-personal-access-token
# to create an API token, and give it access to public repositories.
if [ -z "${GITHUB_AUTH}" ]
then
  AUTH=""
else
  AUTH=" --github-auth $GITHUB_AUTH"
fi

function runCommandAndCompareToSnapshot {
    local LOCAL_COMMAND=$1
    local TITLE=$2
    local ARGS=$3
    local FILE=$4

    echo -ne "- $TITLE: \x1B[34m elm-review --FOR-TESTS $ARGS\x1B[0m"
    if [ ! -f "$SNAPSHOTS/$FILE" ]
    then
      echo -e "\n  \x1B[31mThere is no snapshot recording for \x1B[33m$FILE\x1B[31m\nRun \x1B[33m\n    npm run test-run-record -s\n\x1B[31mto generate it.\x1B[0m"
      exit 1
    fi

    eval "$LOCAL_COMMAND$AUTH --FOR-TESTS $ARGS" 2>&1 | $REPLACE_SCRIPT \
        > "$TMP/$FILE"
    if [ "$(diff "$TMP/$FILE" "$SNAPSHOTS/$FILE")" != "" ]
    then
        echo -e "\x1B[31m  ERROR\n  I found a different output than expected:\x1B[0m"
        echo -e "\n    \x1B[31mExpected:\x1B[0m\n"
        cat "$SNAPSHOTS/$FILE"
        echo -e "\n    \x1B[31mbut got:\x1B[0m\n"
        cat "$TMP/$FILE"
        echo -e "\n    \x1B[31mHere is the difference:\x1B[0m\n"
        diff -p "$TMP/$FILE" "$SNAPSHOTS/$FILE"
        exit 1
    else
      echo -e "  \x1B[92mOK\x1B[0m"
    fi
}

function runAndRecord {
    local LOCAL_COMMAND=$1
    local TITLE=$2
    local ARGS=$3
    local FILE=$4
    echo -e "\x1B[33m- $TITLE\x1B[0m: \x1B[34m elm-review --FOR-TESTS $ARGS\x1B[0m"
    eval "$LOCAL_COMMAND$AUTH --FOR-TESTS $ARGS" 2>&1 | $REPLACE_SCRIPT \
        > "$SNAPSHOTS/$FILE"
}

function createExtensiveTestSuite {
    local LOCAL_COMMAND=$1
    local TITLE=$2
    local ARGS=$3
    local FILE=$4
    createTestSuiteWithDifferentReportFormats "$LOCAL_COMMAND" "$TITLE" "$ARGS" "$FILE"
    createTestSuiteWithDifferentReportFormats "$LOCAL_COMMAND" "$TITLE (debug)" "$ARGS --debug" "$FILE-debug"
}

function createTestSuiteWithDifferentReportFormats {
    local LOCAL_COMMAND=$1
    local TITLE=$2
    local ARGS=$3
    local FILE=$4
    $createTest "$LOCAL_COMMAND" \
        "$TITLE" \
        "$ARGS" \
        "$FILE.txt"
    $createTest "$LOCAL_COMMAND" \
        "$TITLE (JSON)" \
        "$ARGS --report=json" \
        "$FILE-json.txt"
    $createTest "$LOCAL_COMMAND" \
        "$TITLE (Newline delimited JSON)" \
        "$ARGS --report=ndjson" \
        "$FILE-ndjson.txt"
}

function createTestSuiteForHumanAndJson {
    local LOCAL_COMMAND=$1
    local TITLE=$2
    local ARGS=$3
    local FILE=$4
    $createTest "$LOCAL_COMMAND" \
        "$TITLE" \
        "$ARGS" \
        "$FILE.txt"
    $createTest "$LOCAL_COMMAND" \
        "$TITLE (JSON)" \
        "$ARGS --report=json" \
        "$FILE-json.txt"
}

function initElmProject {
  echo Y | npx --no-install elm init > /dev/null
  echo -e 'module A exposing (..)\nimport Html exposing (text)\nmain = text "Hello!"\n' > src/Main.elm
}

function checkFolderContents {
  if [ "$SUBCOMMAND" != "record" ]
  then
    echo -n "  Checking generated files are the same"
    if [ "$(diff -rq "$TMP/$1/" "$SNAPSHOTS/$1/" --exclude="elm-stuff")" != "" ]
    then
        echo -e "\x1B[31m  ERROR\n  The generated files are different:\x1B[0m"
        diff -rq "$TMP/$1/" "$SNAPSHOTS/$1/" --exclude="elm-stuff"
        exit 1
    else
      echo -e "  \x1B[92mOK\x1B[0m"
    fi
  fi
}

function createAndGoIntoFolder {
  if [ "$SUBCOMMAND" != "record" ]
  then
    mkdir -p "$TMP/$1"
    cd "$TMP/$1"
  else
    mkdir -p "$SNAPSHOTS/$1"
    cd "$SNAPSHOTS/$1"
  fi
}

rm -rf "$TMP" \
      "$CWD/config-empty/elm-stuff" \
      "$CWD/config-error-debug/elm-stuff" \
      "$CWD/config-error-unknown-module/elm-stuff" \
      "$CWD/config-for-outdated-elm-review-version/elm-stuff" \
      "$CWD/config-for-salvageable-elm-review-version/elm-stuff" \
      "$CWD/config-syntax-error/elm-stuff" \
      "$CWD/config-that-triggers-no-errors/elm-stuff" \
      "$CWD/config-unparsable-elmjson/elm-stuff" \
      "$CWD/config-without-elm-review/elm-stuff" \
      "$CWD/project-using-es2015-module/elm-stuff" \
      "$CWD/project-with-errors/elm-stuff" \
      "$CWD/project-with-suppressed-errors/elm-stuff"

mkdir -p "$TMP"

if [ "$1" == "record" ]
then
  createTest=runAndRecord
  rm -rf "$SNAPSHOTS" &> /dev/null
  mkdir -p "$SNAPSHOTS"
else
  createTest=runCommandAndCompareToSnapshot
  echo -e '\x1B[33m-- Testing runs\x1B[0m'
fi

PACKAGE_PATH=$(npm pack -s ../ | tail -n 1)
echo "Package path is $PACKAGE_PATH"
npm install -g $PACKAGE_PATH

# init

INIT_PROJECT_NAME="init-project"

createAndGoIntoFolder $INIT_PROJECT_NAME

initElmProject
$createTest "echo Y | $CMD" \
    "Init a new configuration" \
    "init" \
    "init.txt"

checkFolderContents $INIT_PROJECT_NAME

# init with template

INIT_TEMPLATE_PROJECT_NAME="init-template-project"

createAndGoIntoFolder $INIT_TEMPLATE_PROJECT_NAME

initElmProject
$createTest "echo Y | $CMD" \
    "Init a new configuration using a template" \
    "init --template jfmengels/elm-review-unused/example" \
    "init-template.txt"

checkFolderContents $INIT_TEMPLATE_PROJECT_NAME

# FIXES

if [ "$1" == "record" ]
then
  rm -rf "$SNAPSHOTS/project to fix"
  cp -r "$CWD/project-with-errors" "$SNAPSHOTS/project to fix"
  cd "$SNAPSHOTS/project to fix"
else
  rm -rf "$TMP/project to fix"
  cp -r "$CWD/project-with-errors" "$TMP/project to fix"
  cd "$TMP/project to fix"
fi

$createTest "$CMD" \
    "Running with --fix-all-without-prompt" \
    "--fix-all-without-prompt" \
    "fix-all.txt"

if [ "$1" != "record" ]
then
    if [ "$(diff -yq "$TMP/project to fix/src/Main.elm" "$SNAPSHOTS/project to fix/src/Main.elm")" != "" ]
    then
        echo -e "Running with --fix-all-without-prompt (looking at code)"
        echo -e "\x1B[31m  ERROR\n  I found a different FIX output  for Main.elmthan expected:\x1B[0m"
        echo -e "\n    \x1B[31mHere is the difference:\x1B[0m\n"
        diff -py "$TMP/project to fix/src/Main.elm" "$SNAPSHOTS/project to fix/src/Main.elm"
        exit 1
    fi
    if [ "$(diff -yq "$TMP/project to fix/src/Folder/Used.elm" "$SNAPSHOTS/project to fix/src/Folder/Used.elm")" != "" ]
    then
        echo -e "Running with --fix-all-without-prompt (looking at code)"
        echo -e "\x1B[31m  ERROR\n  I found a different FIX output than expected for Folder/Used.elm:\x1B[0m"
        echo -e "\n    \x1B[31mHere is the difference:\x1B[0m\n"
        diff -py "$TMP/project to fix/src/Folder/Used.elm" "$SNAPSHOTS/project to fix/src/Folder/Used.elm"
        exit 1
    fi
    if [ "$(diff -yq "$TMP/project to fix/src/Folder/Unused.elm" "$SNAPSHOTS/project to fix/src/Folder/Unused.elm")" != "" ]
    then
        echo -e "Running with --fix-all-without-prompt (looking at code)"
        echo -e "\x1B[31m  ERROR\n  I found a different FIX output than expected for Folder/Unused.elm:\x1B[0m"
        echo -e "\n    \x1B[31mHere is the difference:\x1B[0m\n"
        diff -py "$TMP/project to fix/src/Folder/Unused.elm" "$SNAPSHOTS/project to fix/src/Folder/Unused.elm"
        exit 1
    fi
fi

## suppress

cd "$CWD/project-with-suppressed-errors"
createTestSuiteForHumanAndJson "$CMD" \
    "Running with only suppressed errors should not report any errors" \
    "" \
    "suppressed-errors-pass"

cp fixed-elm.json elm.json
$createTest "$CMD" \
    "Fixing all errors for an entire rule should remove the suppression file" \
    "" \
    "suppressed-errors-after-fixed-errors-for-rule.txt"
if [ -f review/suppressed/NoUnused.Dependencies.json ]; then
    echo "Expected project-with-suppressed-errors/review/suppressed/NoUnused.Dependencies.json to have been deleted"
    exit 1
fi
git checkout HEAD elm.json review/suppressed/ > /dev/null


rm src/OtherFile.elm
$createTest "$CMD" \
    "Fixing all errors for an entire rule should update the suppression file" \
    "" \
    "suppressed-errors-after-fixed-errors-for-file.txt"

if [ "$(diff review/suppressed/NoUnused.Variables.json expected-NoUnused.Variables.json)" != "" ]; then
    echo "Expected project-with-suppressed-errors/review/suppressed/NoUnused.Variables.json to have been updated"
    exit 1
fi
git checkout HEAD src/OtherFile.elm review/suppressed/ > /dev/null

cp with-errors-OtherFile.elm src/OtherFile.elm
createTestSuiteForHumanAndJson "$CMD" \
    "Introducing new errors should show all related errors" \
    "" \
    "suppressed-errors-introducing-new-errors"
git checkout HEAD src/OtherFile.elm > /dev/null

cd "$CWD"

# new-package

if [ "$1" == "record" ]
then
  cd "$SNAPSHOTS/"
else
  cd "$TMP/"
fi

NEW_PACKAGE_NAME="elm-review-something"
NEW_PACKAGE_NAME_FOR_NEW_RULE="$NEW_PACKAGE_NAME-for-new-rule"

$createTest "$CMD" \
    "Creating a new package" \
    "new-package --prefill some-author,$NEW_PACKAGE_NAME,BSD-3-Clause No.Doing.Foo" \
    "new-package.txt"

checkFolderContents $NEW_PACKAGE_NAME

# new-rule (DEPENDS ON PREVIOUS STEP!)

cp -r $NEW_PACKAGE_NAME $NEW_PACKAGE_NAME_FOR_NEW_RULE
cd $NEW_PACKAGE_NAME_FOR_NEW_RULE

$createTest "$CMD" \
    "Creating a new rule" \
    "new-rule SomeRule" \
    "new-rule.txt"

checkFolderContents $NEW_PACKAGE_NAME_FOR_NEW_RULE

cd "$CWD/project-with-errors"

createTestSuiteWithDifferentReportFormats "$CMD" \
    "Filter rules" \
    "--rules NoUnused.Variables" \
    "filter-rules"

$createTest "$CMD" \
    "Filter rules with comma-separated list" \
    "--rules NoUnused.Variables,NoUnused.Modules" \
    "filter-rules-comma.txt"

$createTest "$CMD" \
    "Filter rules with multiple --rules calls" \
    "--rules NoUnused.Variables --rules NoUnused.Modules" \
    "filter-rules-multiple-calls.txt"

createTestSuiteWithDifferentReportFormats "$CMD" \
    "Filter unknown rule" \
    "--rules NoUnused.Unknown" \
    "filter-unknown-rule"

$createTest "$CMD" \
  "Ignore errors on directories" \
  "--ignore-dirs src/Folder/" \
  "ignore-dirs.txt"

$createTest "$CMD" \
  "Ignore errors on files" \
  "--ignore-files src/Folder/Unused.elm" \
  "ignore-files.txt"

# Review with remote configuration

$createTest "$CMD" \
    "Running using remote GitHub configuration" \
    "--template jfmengels/elm-review-unused/example" \
    "remote-configuration.txt"

$createTest "$CMD" \
    "Running using remote GitHub configuration (no errors)" \
    "--template jfmengels/node-elm-review/test/config-that-triggers-no-errors" \
    "remote-configuration-no-errors.txt"

$createTest "$CMD" \
    "Running using remote GitHub configuration without a path to the config" \
    "--template jfmengels/test-node-elm-review" \
    "remote-configuration-no-path.txt"

createTestSuiteWithDifferentReportFormats "$CMD" \
    "Using unknown remote GitHub configuration" \
    "--template jfmengels/unknown-repo-123" \
    "remote-configuration-unknown"

createTestSuiteWithDifferentReportFormats "$CMD" \
    "Using unknown remote GitHub configuration with a branch" \
    "--template jfmengels/unknown-repo-123#some-branch" \
    "remote-configuration-unknown-with-branch"

createTestSuiteWithDifferentReportFormats "$CMD" \
    "Using remote GitHub configuration with a non-existing branch and commit" \
    "--template jfmengels/elm-review-unused/example#unknown-branch" \
    "remote-configuration-with-unknown-branch"

createTestSuiteWithDifferentReportFormats "$CMD" \
    "Using remote GitHub configuration with existing repo but that does not contain template folder" \
    "--template jfmengels/node-elm-review" \
    "remote-configuration-with-absent-folder"

createTestSuiteWithDifferentReportFormats "$CMD" \
    "Using a remote configuration with a missing direct elm-review dependency" \
    "--template jfmengels/node-elm-review/test/config-without-elm-review" \
    "remote-without-elm-review"

createTestSuiteWithDifferentReportFormats "$CMD" \
    "Using a remote configuration with an outdated elm-review" \
    "--template jfmengels/node-elm-review/test/config-for-outdated-elm-review-version" \
    "remote-with-outdated-elm-review-version"

createTestSuiteWithDifferentReportFormats "$CMD" \
    "Using a remote configuration with an salvageable (outdated but compatible) elm-review" \
    "--template jfmengels/node-elm-review/test/config-for-salvageable-elm-review-version" \
    "remote-with-outdated-but-salvageable-elm-review-version"

createTestSuiteWithDifferentReportFormats "$CMD" \
    "Using a remote configuration with unparsable elm.json" \
    "--template jfmengels/node-elm-review/test/config-unparsable-elmjson" \
    "remote-configuration-with-unparsable-elmjson"

createTestSuiteWithDifferentReportFormats "$CMD" \
    "Using both --config and --template" \
    "--config ../config-that-triggers-no-errors --template jfmengels/test-node-elm-review" \
    "remote-configuration-with-config-flag"

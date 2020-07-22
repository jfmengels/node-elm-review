#!/bin/bash

CWD=$(pwd)
CMD="$CWD/../bin/elm-review"
TMP="$CWD/tmp"
SNAPSHOTS="$CWD/snapshots"

function runCommandAndCompareToSnapshot {
    local TITLE=$1
    local ARGS=$2
    local FILE=$3

    echo -ne "- $TITLE: \e[34m elm-review --FOR-TESTS $ARGS\e[0m"
    if [ ! -f "$SNAPSHOTS/$FILE" ]
    then
      echo -e "\n  \e[31mThere is no snapshot recording for \e[33m$FILE\e[31m\nRun \e[33m\n    npm run test-run-record -s\n\e[31mto generate it.\e[0m"
      exit 1
    fi

    $CMD --FOR-TESTS $ARGS &> "$TMP/$FILE"
    if [ "$(diff "$TMP/$FILE" "$SNAPSHOTS/$FILE")" != "" ]
    then
        echo -e "\e[31m  ERROR\n  I found a different output than expected:\e[0m"
        echo -e "\n    \e[31mExpected:\e[0m\n"
        cat "$SNAPSHOTS/$FILE"
        echo -e "\n    \e[31mbut got:\e[0m\n"
        cat "$TMP/$FILE"
        echo -e "\n    \e[31mHere is the difference:\e[0m\n"
        diff "$TMP/$FILE" "$SNAPSHOTS/$FILE"
        exit 1
    else
      echo -e "  \e[92mOK\e[0m"
    fi
}

function runAndRecord {
    local TITLE=$1
    local ARGS=$2
    local FILE=$3
    echo -e "\e[33m- $TITLE\e[0m: \e[34m elm-review --FOR-TESTS $ARGS\e[0m"
    $CMD --FOR-TESTS $ARGS > "$SNAPSHOTS/$FILE"
}

function createExtensiveTestSuite {
    local TITLE=$1
    local ARGS=$2
    local FILE=$3
    createTestSuiteWithDifferentReportFormats "$TITLE" "$ARGS" "$FILE"
    createTestSuiteWithDifferentReportFormats "$TITLE (debug)" "$ARGS --debug" "$FILE-debug"
}

function createTestSuiteWithDifferentReportFormats {
    local TITLE=$1
    local ARGS=$2
    local FILE=$3
    $createTest "$TITLE" \
        "$ARGS" \
        "$FILE.txt"
    $createTest "$TITLE (JSON)" \
        "$ARGS --report=json" \
        "$FILE-json.txt"
}

rm -r $TMP \
      project-with-errors/elm-stuff/generated-code/jfmengels/elm-review/cli/*/review-applications/
mkdir -p $TMP

if [ "$1" == "record" ]
then
  createTest=runAndRecord
  rm -r $SNAPSHOTS
  mkdir -p $SNAPSHOTS
else
  createTest=runCommandAndCompareToSnapshot
  echo -e '\e[33m-- Testing runs\e[0m'
fi

# Version

$createTest \
    "Running with --version" \
    "--version" \
    "version.txt"

# Help

$createTest \
    "Running with --help" \
    "--help" \
    "help-main.txt"

$createTest \
    "Running init with --help" \
    "init --help" \
    "help-init.txt"

$createTest \
    "Running new-package with --help" \
    "new-package --help" \
    "help-new-package.txt"

$createTest \
    "Running new-rule with --help" \
    "new-rule --help" \
    "help-new-rule.txt"


# Review

cd project-with-errors
createExtensiveTestSuite \
    "Regular run from inside the project" \
    "" \
    "simple-run"

createTestSuiteWithDifferentReportFormats \
    "Running using other configuration (without errors)" \
    "--config ../config-that-triggers-no-errors" \
    "no-errors"

# Review with remote configuration

$createTest \
    "Running using remote GitHub configuration" \
    "--template jfmengels/review-unused#example" \
    "remote-configuration.txt"

createTestSuiteWithDifferentReportFormats \
    "Using unknown remote GitHub configuration" \
    "--template jfmengels/unknown-repo-123" \
    "remote-configuration-unknown"

createTestSuiteWithDifferentReportFormats \
    "Using unknown remote GitHub configuration with a branch" \
    "--template jfmengels/unknown-repo-123#some-branch" \
    "remote-configuration-unknown-with-branch"

createTestSuiteWithDifferentReportFormats \
    "Using remote GitHub configuration with a non-existing branch and commit" \
    "--template jfmengels/review-unused#unknown-branch" \
    "remote-configuration-with-unknown-branch"

createTestSuiteWithDifferentReportFormats \
    "Using remote GitHub configuration with existing repo but that does not contain template folder" \
    "--template jfmengels/node-elm-review" \
    "remote-configuration-with-absent-folder"

cd ..
# # This is failing at the moment
# $createTest "Regular run using --elmjson and --config" \
#             "--elmjson project-with-errors/elm.json --config project-with-errors/review" \
#             "regular-run-snapshot"

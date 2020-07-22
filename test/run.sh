#!/bin/bash

CWD=$(pwd)
CMD="$CWD/../bin/elm-review"
TMP="$CWD/tmp"
SNAPSHOTS="$CWD/snapshots"

function runCommandAndCompareToSnapshot {
    local TITLE=$1
    local ARGS=$2
    local FILE=$3
    echo "$FILE"

    echo -ne "- $TITLE: \e[34m elm-review $ARGS\e[0m"
    if [ ! -f "$SNAPSHOTS/$FILE" ]
    then
      echo -e "\n  \e[31mThere is no snapshot recording for \e[33m$FILE\e[31m\nRun \e[33m\n    npm run test-run-record -s\n\e[31mto generate it.\e[0m"
      exit 1
    fi

    $CMD $ARGS > "$TMP/$FILE"
    local DIFF=$(diff "$TMP/$FILE" "$SNAPSHOTS/$FILE")
    if [ "$DIFF" != "" ]
    then
        echo -e "\e[31m  ERROR\n  I found a different output than expected:\e[0m"
        echo -e "\n    \e[31mExpected:\e[0m\n"
        cat $FILE
        echo -e "\n    \e[31mbut got:\e[0m\n"
        cat "$TMP/$FILE"
        echo -e "\n    \e[31mHere is the difference:\e[0m\n"
        echo -e $DIFF
        exit 1
    else
      echo -e "  \e[92mOK\e[0m"
    fi
}

function runAndRecord {
    local TITLE=$1
    local ARGS=$2
    local FILE=$3
    echo -e "\e[33m- $TITLE\e[0m: \e[34m elm-review $ARGS\e[0m"
    $CMD $ARGS > "$SNAPSHOTS/$FILE"
}

function createTestCaseInMultipleScenariis {
    local TITLE=$1
    local ARGS=$2
    local FILE=$3
    $createTest "$TITLE" \
        "$ARGS" \
        "$FILE.txt"
    $createTest "$TITLE (debug)" \
        "$ARGS --debug" \
        "$FILE-debug.txt"
    $createTest "$TITLE (JSON)" \
        "$ARGS --report=json" \
        "$FILE-json.txt"
    $createTest "$TITLE (debug+JSON)" \
        "$ARGS --debug --report=json" \
        "$FILE-debug-json.txt"
}

rm -rf $TMP
mkdir -p $TMP

if [ "$1" == "record" ]
then
  createTest=runAndRecord
  rm -rf $SNAPSHOTS
  mkdir -p $SNAPSHOTS
else
  createTest=runCommandAndCompareToSnapshot
  echo -e '\e[33m-- Testing runs\e[0m'
fi

cd project-with-errors
createTestCaseInMultipleScenariis \
    "Regular run from inside the project" \
    "" \
    "simple-run"

createTestCaseInMultipleScenariis \
    "Running using other script (without errors)" \
    "--config ../config-that-triggers-no-errors" \
    "no-errors"

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

# cd ..
# # This is failing at the moment
# $createTest "Regular run using --elmjson and --config" \
#             "--elmjson project-with-errors/elm.json --config project-with-errors/review" \
#             "regular-run-snapshot"
# exit 0

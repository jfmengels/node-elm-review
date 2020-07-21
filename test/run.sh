#!/bin/bash

CWD=$(pwd)
CMD="$CWD/../bin/elm-review"
TMP="$CWD/tmp"
SNAPSHOTS="$CWD/snapshots"

function runCommandAndCompareToSnapshot {
    TITLE=$1
    ARGS=$2
    FILE=$3

    echo -ne "- $TITLE: \e[34m elm-review $ARGS\e[0m"
    if [ ! -f "$SNAPSHOTS/$FILE" ]
    then
      echo -e "\n  \e[31mThere is no snapshot recording for \e[33m$FILE\e[31m\nRun \e[33m\n    npm run test-run-record -s\n\e[31mto generate it.\e[0m"
      exit 1
    fi

    $CMD $ARGS > "$TMP/$FILE"
    DIFF=$(diff "$TMP/$FILE" "$SNAPSHOTS/$FILE")
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
    TITLE=$1
    ARGS=$2
    FILE=$3
    $CMD $ARGS > "$SNAPSHOTS/$FILE"
}

if [ "$1" == "record" ]
then
  createTest=runAndRecord
else
  createTest=runCommandAndCompareToSnapshot
  echo -e '\e[33m-- Testing runs\e[0m'
fi

rm -rf $TMP
mkdir -p $TMP

cd project-with-errors
$createTest "Regular run from inside the project" \
            "" \
            "regular-run-snapshot.txt"

# cd ..
# # This is failing at the moment
# $createTest "Regular run using --elmjson and --config" \
#             "--elmjson project-with-errors/elm.json --config project-with-errors/review" \
#             "regular-run-snapshot.txt"
# exit 0

$createTest "With debug mode" \
            "--debug" \
            "debug-mode-snapshot.txt"

$createTest "With debug and JSON report" \
            "--debug --report=json" \
            "json-debug-report-snapshot.txt"

$createTest "With JSON report" \
            "--report=json" \
            "json-report-snapshot.txt"

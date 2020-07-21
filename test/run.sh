#!/bin/bash

cmd="../../bin/elm-review"

function runCommandAndCompareToSnapshot {
    title=$1
    args=$2
    file=$3
    mkdir -p "elm-stuff"

    if [ ! -f "$file" ]
    then
      echo -e "\e[31mThere is no snapshot recording for \e[33m$file\e[31m\nRun \e[33m\n    npm run test-run-record -s\n\e[31mto generate it.\e[0m"
      exit 1
    fi

    $cmd $args > "elm-stuff/$file"
    DIFF=$(diff "elm-stuff/$file" $file || exit 1)
    if [ "$DIFF" != "" ]
    then
        echo -e "\e[31mTest \"$title\" resulted in a different output than expected:\e[0m"
        echo -e "\n    \e[31mExpected:\e[0m\n"
        cat $file
        echo -e "\n    \e[31mbut got:\e[0m\n"
        cat "elm-stuff/$file"
        echo -e "\n    \e[31mHere is the difference:\e[0m\n"
        echo -e $DIFF
        exit 1
    else
      echo -e "\e[92m$title: OK\e[0m"
    fi
}

function runAndRecord {
    title=$1
    args=$2
    file=$3
    $cmd $args > "$file"
}

if [ "$1" == "record" ]
then
  createTest=runAndRecord
else
  createTest=runCommandAndCompareToSnapshot
  echo -e '\e[33m-- Testing runs\e[0m'
fi

cd project-with-errors
rm -rf elm-stuff
$createTest "Regular run" "" "regular-run-snapshot.txt"
$createTest "With debug mode" "--debug" "debug-mode-snapshot.txt"
$createTest "With debug mode (second run)" "--debug" "debug-mode-second-run-snapshot.txt"
$createTest "With debug and JSON report" "--debug --report=json" "json-debug-report-snapshot.txt"
$createTest "With JSON report" "--report=json" "json-report-snapshot.txt"
exit 0

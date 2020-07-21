#!/bin/bash

cmd="../../bin/elm-review"

function runCommandAndCompareTo {
    title=$1
    args=$2
    file=$3
    mkdir -p "elm-stuff"
    $cmd $args > "elm-stuff/$file"
    DIFF=$(diff "elm-stuff/$file" $file)
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
    args=$1
    file=$2
    $cmd $args > "$file"
}

if [ "$1" == "record" ]
then
  cd project-with-errors
  rm -rf elm-stuff
  runAndRecord "" "regular-run-snapshot.txt"
  runAndRecord "--report=json" "json-report-snapshot.txt"
  runAndRecord "--debug" "debug-mode-snapshot.txt"
  runAndRecord "--debug" "debug-mode-second-run-snapshot.txt"
  exit 0
else
  echo -e '\e[33m-- Testing runs\e[0m'
  cd project-with-errors
  rm -rf elm-stuff
  runCommandAndCompareTo "Regular run" "" "regular-run-snapshot.txt"
  runCommandAndCompareTo "With JSON report" "--report=json" "json-report-snapshot.txt"
  runCommandAndCompareTo "With debug mode" "--debug" "debug-mode-snapshot.txt"
  runCommandAndCompareTo "With debug mode (second run)" "--debug" "debug-mode-second-run-snapshot.txt"
  exit 0
fi

#!/bin/bash
echo -e '\e[33m-- Testing the run\e[0m\n'

cd project-with-errors

cmd="../../bin/elm-review"

function runCommandAndCompareTo {
    title=$1
    args=$2
    file=$3
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

runCommandAndCompareTo "Regular run" "" "test-result-snapshot.txt"

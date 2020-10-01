#!/bin/bash

CWD=$(pwd)
CMD="$CWD/../bin/elm-review"
TMP="$CWD/tmp"
SNAPSHOTS="$CWD/snapshots"
SUBCOMMAND="$1"

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

ESCAPED_PWD=$(echo $CWD | sed 's_/_\\/_g')

function runCommandAndCompareToSnapshot {
    local LOCAL_COMMAND=$1
    local TITLE=$2
    local ARGS=$3
    local FILE=$4

    echo -ne "- $TITLE: \e[34m elm-review --FOR-TESTS $ARGS\e[0m"
    if [ ! -f "$SNAPSHOTS/$FILE" ]
    then
      echo -e "\n  \e[31mThere is no snapshot recording for \e[33m$FILE\e[31m\nRun \e[33m\n    npm run test-run-record -s\n\e[31mto generate it.\e[0m"
      exit 1
    fi

    eval "$LOCAL_COMMAND$AUTH --FOR-TESTS $ARGS &> \"$TMP/$FILE\""
    sed -i "s/$ESCAPED_PWD/<local-path>/" "$TMP/$FILE"
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
    local LOCAL_COMMAND=$1
    local TITLE=$2
    local ARGS=$3
    local FILE=$4
    echo -e "\e[33m- $TITLE\e[0m: \e[34m elm-review --FOR-TESTS $ARGS\e[0m"
    eval "$LOCAL_COMMAND$AUTH --FOR-TESTS $ARGS &> \"$SNAPSHOTS/$FILE\""
    sed -i "s/$ESCAPED_PWD/<local-path>/" "$SNAPSHOTS/$FILE"
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
        echo -e "\e[31m  ERROR\n  The generated files are different:\e[0m"
        echo "$(diff -rq "$TMP/$1/" "$SNAPSHOTS/$1/" --exclude="elm-stuff")"
        exit 1
    else
      echo -e "  \e[92mOK\e[0m"
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

rm -r $TMP \
      project-with-errors/elm-stuff/generated-code/jfmengels/elm-review/cli/*/review-applications/ \
      project-with-errors/elm-stuff/generated-code/jfmengels/elm-review/cli/*/remote-templates/ \
      &> /dev/null
mkdir -p $TMP
npm run build > /dev/null

if [ "$1" == "record" ]
then
  createTest=runAndRecord
  rm -r $SNAPSHOTS &> /dev/null
  mkdir -p $SNAPSHOTS
else
  createTest=runCommandAndCompareToSnapshot
  echo -e '\e[33m-- Testing runs\e[0m'
fi

# Version

$createTest "$CMD" \
    "Running with --version" \
    "--version" \
    "version.txt"

# Help

$createTest "$CMD" \
    "Running with --help" \
    "--help" \
    "help-main.txt"

$createTest "$CMD" \
    "Running init with --help" \
    "init --help" \
    "help-init.txt"

$createTest "$CMD" \
    "Running new-package with --help" \
    "new-package --help" \
    "help-new-package.txt"

$createTest "$CMD" \
    "Running new-rule with --help" \
    "new-rule --help" \
    "help-new-rule.txt"

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

# Review

cd $CWD/project-with-errors
createExtensiveTestSuite "$CMD" \
    "Regular run from inside the project" \
    "" \
    "simple-run"

createTestSuiteWithDifferentReportFormats "$CMD" \
    "Running using other configuration (without errors)" \
    "--config ../config-that-triggers-no-errors" \
    "no-errors"

cd $CWD
createTestSuiteWithDifferentReportFormats "$CMD" \
    "Regular run using --elmjson and --config" \
    "--elmjson project-with-errors/elm.json --config project-with-errors/review" \
    "run-with-elmjson-flag"
cd $CWD/project-with-errors

createTestSuiteWithDifferentReportFormats "$CMD" \
    "Using an empty configuration" \
    "--config ../config-empty" \
    "config-empty"

createTestSuiteWithDifferentReportFormats "$CMD" \
    "Using a configuration with a missing direct elm-review dependency" \
    "--config ../config-without-elm-review" \
    "without-elm-review"

createTestSuiteWithDifferentReportFormats "$CMD" \
    "Using a configuration with an outdated elm-review package" \
    "--config ../config-for-outdated-elm-review-version" \
    "outdated-version"

createTestSuiteWithDifferentReportFormats "$CMD" \
    "Using an configuration which fails due to unknown module" \
    "--config ../config-error-unknown-module" \
    "config-error-unknown-module"

createTestSuiteWithDifferentReportFormats "$CMD" \
    "Using an configuration which fails due to syntax error" \
    "--config ../config-syntax-error" \
    "config-syntax-error"

createTestSuiteWithDifferentReportFormats "$CMD" \
    "Using an configuration which fails due to debug remnants" \
    "--config ../config-error-debug" \
    "config-error-debug"

# new-package

if [ "$1" == "record" ]
then
  cd $SNAPSHOTS/
else
  cd $TMP/
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

cd $CWD/project-with-errors

createTestSuiteWithDifferentReportFormats "$CMD" \
    "Filter rules" \
    "--rules NoUnused.Variables" \
    "filter-rules"

createTestSuiteWithDifferentReportFormats "$CMD" \
    "Filter unknown rule" \
    "--rules NoUnused.Unknown" \
    "filter-unknown-rule"

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

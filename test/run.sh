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

cd "$CWD/project-with-suppressed-errors"
$createTest "$CMD" \
    "Running with only suppressed errors should not report any errors" \
    "" \
    "suppressed-errors-pass.txt"

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
    echo "Expected project-with-suppressed-errors/review/suppressed/NoUnused.Dependencies.json to have been deleted"
    exit 1
fi
git checkout HEAD src/OtherFile.elm review/suppressed/ > /dev/null

cp with-errors-OtherFile.elm src/OtherFile.elm
$createTest "$CMD" \
    "Introducing new errors should show all related errors" \
    "" \
    "suppressed-errors-introducing-new-errors.txt"
git checkout HEAD src/OtherFile.elm > /dev/null

$createTest "$CMD" \
    "Running with --unsuppress should report suppressed errors" \
    "--unsuppress" \
    "suppressed-errors-unsuppress.txt"

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
    "Running suppress with --help" \
    "suppress --help" \
    "help-suppress.txt"

exit 0

$createTest "$CMD" \
    "Running new-package with --help" \
    "new-package --help" \
    "help-new-package.txt"

$createTest "$CMD" \
    "Running new-rule with --help" \
    "new-rule --help" \
    "help-new-rule.txt"

# Unknown flags

$createTest "$CMD" \
    "Running with an unknown flag" \
    "--watc" \
    "unknown-flag.txt"

$createTest "$CMD" \
    "Running with an unknown shorthand flag" \
    "-u" \
    "unknown-shorthand-flag.txt"

# Flag errors

$createTest "$CMD" \
    "Running --compiler without an argument" \
    "--compiler" \
    "missing-argument-compiler.txt"

$createTest "$CMD" \
    "Running --config without an argument" \
    "--config" \
    "missing-argument-config.txt"

$createTest "$CMD" \
    "Running --template without an argument" \
    "--template" \
    "missing-argument-template.txt"

$createTest "$CMD" \
    "Running --elmjson without an argument" \
    "--elmjson" \
    "missing-argument-elmjson.txt"

$createTest "$CMD" \
    "Running --report without an argument" \
    "--report" \
    "missing-argument-report.txt"

$createTest "$CMD" \
    "Running --elm-format-path without an argument" \
    "--elm-format-path" \
    "missing-argument-elm-format-path.txt"

$createTest "$CMD" \
    "Running --rules without an argument" \
    "--rules" \
    "missing-argument-rules.txt"

$createTest "$CMD" \
    "Running --ignore-dirs without an argument" \
    "--ignore-dirs" \
    "missing-argument-ignore-dirs.txt"

$createTest "$CMD" \
    "Running --ignore-files without an argument" \
    "--ignore-files" \
    "missing-argument-ignore-files.txt"

$createTest "$CMD" \
    "Running init --compiler without an argument" \
    "init --compiler" \
    "missing-argument-init-compiler.txt"

$createTest "$CMD" \
    "Running init --config without an argument" \
    "init --config" \
    "missing-argument-init-config.txt"

$createTest "$CMD" \
    "Running init --template without an argument" \
    "init --template" \
    "missing-argument-init-template.txt"

$createTest "$CMD" \
    "Running new-package --compiler without an argument" \
    "new-package --compiler" \
    "missing-argument-new-package-compiler.txt"

# Temporarily disabling auth because otherwise `--github-auth` would be duplicated
OLD_AUTH="$AUTH"
AUTH=""
$createTest "$CMD" \
    "Running --github-auth with a bad value" \
    "--github-auth=bad" \
    "github-auth-bad-argument.txt"
AUTH="$OLD_AUTH"

$createTest "$CMD" \
    "Running --report with an unknown value" \
    "--report=unknown" \
    "report-unknown-argument.txt"

$createTest "$CMD" \
    "Running --template with a bad value" \
    "--template=not-github-repo" \
    "template-bad-argument.txt"

$createTest "$CMD" \
    "Running init --template with a bad value" \
    "init --template=not-github-repo" \
    "init-template-bad-argument.txt"

$createTest "$CMD" \
    "Using the same flag twice" \
    "--config a/ --config b/" \
    "duplicate-flags.txt"

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

cd "$CWD/project-with-errors"
createExtensiveTestSuite "$CMD" \
    "Regular run from inside the project" \
    "" \
    "simple-run"

createTestSuiteWithDifferentReportFormats "$CMD" \
    "Running using other configuration (without errors)" \
    "--config ../config-that-triggers-no-errors" \
    "no-errors"

cd "$CWD"
createTestSuiteWithDifferentReportFormats "$CMD" \
    "Regular run using --elmjson and --config" \
    "--elmjson project-with-errors/elm.json --config project-with-errors/review" \
    "run-with-elmjson-flag"

cd "$CWD/project-using-es2015-module"
createTestSuiteWithDifferentReportFormats "$CMD" \
    "Running in a project using ES2015 modules" \
    "" \
    "config-es2015-modules"

cd "$CWD/project-with-errors"

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
    "Using an configuration which fails due to configuration error" \
    "--config ../config-configuration-error" \
    "config-configuration-error"

createTestSuiteWithDifferentReportFormats "$CMD" \
    "Using an configuration which fails due to debug remnants" \
    "--config ../config-error-debug" \
    "config-error-debug"

$createTest "$CMD" \
    "Running on project with unknown file" \
    "--config ../config-that-triggers-no-errors unknown-target" \
    "run-with-unknown-target.txt"

cd "$CWD/project-with-dir-ending-in-elm"

$createTest "$CMD" \
    "Running on project with a directory ending in .elm" \
    "--config ../config-that-triggers-no-errors" \
    "src.elm-project-without-arg.txt"

$createTest "$CMD" \
    "Running on project with a directory ending in .elm" \
    "--config ../config-that-triggers-no-errors src.elm" \
    "src.elm-project-with-arg.txt"

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

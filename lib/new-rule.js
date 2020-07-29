const path = require('path');
const chalk = require('chalk');
const fs = require('fs-extra');
const prompts = require('prompts');
const errorMessage = require('./error-message');

const packageNameRegex = /.+\/(elm-)?review-.+/;

async function create(options) {
  const elmJson = readElmJson(options);

  if (!elmJson) {
    /* eslint-disable prettier/prettier */
    throw new errorMessage.CustomError("COULD NOT FIND ELM.JSON",
    `I could not find a ${chalk.yellowBright('elm.json')} file. I need you to be inside an Elm project.

You can run ${chalk.cyan('elm-review new-package')} to get started with a new project designed to publish review rules.`)
    /* eslint-enable prettier/prettier */
  }

  if (options.newRuleName) {
    validateRuleName(options.newRuleName);
  }

  const ruleName = options.newRuleName || (await askForRuleName());

  if (ruleName) {
    await addRule(options, elmJson, ruleName);
  }
}

function readElmJson(options) {
  if (!options.elmJsonPath) {
    return null;
  }

  try {
    return fs.readJsonSync(options.elmJsonPath, 'utf8');
  } catch (_) {
    return null;
  }
}

const ruleNameRegex = /^[A-Z][\d\w_]*(\.[A-Z][\d\w_]*)*$/;

function validateRuleName(ruleName) {
  if (!ruleNameRegex.test(ruleName)) {
    throw new errorMessage.CustomError(
      'INVALID RULE NAME',
      'The rule name needs to be a valid module name.'
    );
  }
}

async function askForRuleName() {
  let canceled = false;
  const {ruleName} = await prompts(
    {
      type: 'text',
      name: 'ruleName',
      message: `Name of the rule (ex: No.Doing.Foo):`
    },
    {
      onCancel: () => {
        canceled = true;
        return false;
      }
    }
  );

  if (canceled) {
    return null;
  }

  if (!ruleNameRegex.test(ruleName)) {
    console.log('The rule name needs to a valid module name.');
    return askForRuleName();
  }

  return ruleName;
}

function writeFile(dir, fileName, content) {
  fs.writeFileSync(path.join(dir, fileName), content);
}

async function addRule(options, elmJson, ruleName) {
  const ruleNameFolder = ruleName.split('.').slice(0, -1).join('/');
  const dir = path.dirname(options.elmJsonPath);

  try {
    fs.mkdirpSync(path.join(dir, 'src', ruleNameFolder));
  } catch (_) {}

  try {
    fs.mkdirpSync(path.join(dir, 'tests', ruleNameFolder));
  } catch (_) {}

  console.log(`Adding rule - ${ruleName}`);

  writeFile(
    dir,
    path.join('src', `${ruleName.split('.').join('/')}.elm`),
    newSourceFile(ruleName)
  );
  writeFile(
    dir,
    path.join('tests', `${ruleName.split('.').join('/')}Test.elm`),
    newTestFile(ruleName)
  );

  if (elmJson.type === 'package' && packageNameRegex.test(elmJson.name)) {
    console.log('Exposing the rule in elm.json');
    const newElmJson = {
      ...elmJson,
      'exposed-modules': [...elmJson['exposed-modules'], ruleName].sort()
    };

    writeFile(dir, 'elm.json', JSON.stringify(newElmJson, null, 2));

    console.log('Adding rule to the README');
    try {
      const readmeContent = fs.readFileSync(
        path.join(dir, 'README.md'),
        'utf8'
      );
      injectRuleInReadme(dir, elmJson, ruleName, readmeContent);
    } catch (_) {
      console.log(
        `${chalk.red('[WARNING]')} Could not find a ${chalk.yellow(
          'README.md'
        )}`
      );
    }
  } else {
    console.log(
      `${chalk.yellow('[SKIPPED]')} Exposing the rule in elm.json and README.md`
    );
  }
}

function injectRuleInReadme(dir, elmJson, ruleName, content) {
  const lines = content.split('\n');
  insertRuleDescription(elmJson, ruleName, lines);
  insertRuleInConfiguration(elmJson, ruleName, lines);
  writeFile(dir, 'README.md', lines.join('\n'));
}

const ruleSectionRegex = /#+.*rules.*/i;

// Mutates `lines`!
function insertRuleDescription(elmJson, ruleName, lines) {
  const rulesSectionIndex = lines.findIndex((line) =>
    ruleSectionRegex.test(line)
  );
  if (rulesSectionIndex) {
    const description = ruleDescription(
      elmJson.name,
      elmJson.version,
      ruleName
    );
    lines.splice(rulesSectionIndex + 2, 0, description);
  } else {
    console.log(
      `${chalk.red('[WARNING]')} Could not find a ${chalk.yellow(
        'Provided rules'
      )} section in README to include the rule in`
    );
  }
}

// Mutates `lines`!
function insertRuleInConfiguration(elmJson, ruleName, lines) {
  const someOtherRule = elmJson['exposed-modules'][0];
  insertImport(ruleName, lines);
  insertRuleInConfigList(ruleName, someOtherRule, lines);
}

function insertImport(ruleName, lines) {
  const firstImportIndex = lines.findIndex((line) => line.startsWith('import'));

  if (firstImportIndex === -1) {
    console.log(
      `${chalk.red(
        '[WARNING]'
      )} Could not find where to add an import of the in the example configuration`
    );
    return;
  }

  let numberOfImports = 1;
  while (
    firstImportIndex + numberOfImports < lines.length &&
    lines[firstImportIndex + numberOfImports].startsWith('import')
  ) {
    numberOfImports++;
  }

  const importLines = [
    ...lines.slice(firstImportIndex, firstImportIndex + numberOfImports),
    `import ${ruleName}`
  ].sort();
  lines.splice(firstImportIndex, numberOfImports, ...importLines);
}

function insertRuleInConfigList(ruleName, someOtherRule, lines) {
  const indexOfOtherRuleExample = lines.findIndex((line) =>
    line.includes(`${someOtherRule}.rule`)
  );

  if (indexOfOtherRuleExample === -1) {
    console.log(
      `${chalk.red(
        '[WARNING]'
      )} Could not find an example configuration to include the rule in`
    );
    return;
  }

  const line = lines[indexOfOtherRuleExample];
  if (line.trim().startsWith('[')) {
    lines.splice(indexOfOtherRuleExample + 1, 0, `    , ${ruleName}.rule`);
  } else {
    lines.splice(indexOfOtherRuleExample, 0, `    , ${ruleName}.rule`);
  }
}

function newSourceFile(ruleName) {
  return `module ${ruleName} exposing (rule)

{-|

@docs rule

-}

import Review.Rule as Rule exposing (Rule)


{-| Reports... REPLACEME

    config =
        [ ${ruleName}.rule
        ]


## Fail

    a =
        "REPLACEME example to replace"


## Success

    a =
        "REPLACEME example to replace"


## When (not) to enable this rule

This rule is useful when REPLACEME.
THis rule is not useful when REPLACEME.

-}
rule : Rule
rule =
    Rule.newModuleRuleSchema "${ruleName}" ()
        -- Add your visitors
        |> Rule.fromModuleRuleSchema
`;
}

function newTestFile(ruleName) {
  return `module ${ruleName}Test exposing (all)

import ${ruleName} exposing (rule)
import Review.Test
import Test exposing (Test, describe, test)


all : Test
all =
    describe "${ruleName}"
        [ test "should report an error when REPLACEME" <|
            \\() ->
                """module A exposing (..)
a = 1
"""
                    |> Review.Test.run rule
                    |> Review.Test.expectErrors
                        [ Review.Test.error
                            { message = "REPLACEME"
                            , details = [ "REPLACEME" ]
                            , under = "REPLACEME"
                            }
                        ]
        ]
`;
}

function ruleDescription(packageName, packageVersion, ruleName) {
  const ruleNameAsUrl = ruleName.split('.').join('-');
  return `- [\`${ruleName}\`](https://package.elm-lang.org/packages/${packageName}/${packageVersion}/${ruleNameAsUrl}) - Reports REPLACEME.`;
}

module.exports = {
  create,
  askForRuleName,
  newSourceFile,
  newTestFile,
  ruleDescription,
  validateRuleName
};

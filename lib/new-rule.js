/**
 * @import {Options, ReviewOptions, RuleType} from './types/options';
 * @import {PackageElmJson} from './types/content';
 */
const path = require('node:path');
const chalk = require('chalk');
const fs = require('graceful-fs');
const prompts = require('prompts');
const {glob} = require('tinyglobby');
const ErrorMessage = require('./error-message');
const FS = require('./fs-wrapper');

const packageNameRegex = /.+\/(elm-)?review-.+/;

/**
 * @param {ReviewOptions} options
 * @returns {Promise<void>}
 */
async function create(options) {
  const elmJson = readElmJson(options);

  if (!elmJson) {
    throw new ErrorMessage.CustomError(
      'COULD NOT FIND ELM.JSON',
      // prettier-ignore
      `I could not find a ${chalk.yellow('elm.json')} file. I need you to be inside an Elm project.

You can run ${chalk.cyan('elm-review new-package')} to get started with a new project designed to publish review rules.`
    );
  }

  if (options.newRuleName) {
    validateRuleName(options.newRuleName);
  }

  const ruleName = options.newRuleName ?? (await askForRuleName());
  if (!ruleName) {
    return;
  }

  const ruleType = options.ruleType ?? (await askForRuleType());
  if (!ruleType) {
    return;
  }

  await addRule(options, elmJson, ruleName, ruleType);
}

/**
 * @param {Options} options
 * @returns {PackageElmJson | null}
 */
function readElmJson(options) {
  if (!options.elmJsonPath) {
    return null;
  }

  try {
    return /** @type {PackageElmJson} */ (
      FS.readJsonFileSync(options.elmJsonPath)
    );
  } catch {
    return null;
  }
}

const ruleNameRegex = /^[A-Z]\w*(\.[A-Z]\w*)*$/;

/**
 * @param {string} ruleName
 * @returns {string}
 */
function validateRuleName(ruleName) {
  if (!ruleNameRegex.test(ruleName)) {
    throw new ErrorMessage.CustomError(
      'INVALID RULE NAME',
      'The rule name needs to be a valid Elm module name that only contains characters A-Z, digits and `_`.'
    );
  }

  return ruleName;
}

/**
 * @returns {Promise<string | null>}
 */
async function askForRuleName() {
  let canceled = false;
  /** @type {{ruleName: string}} */
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
    console.log(
      'The rule name needs to be a valid Elm module name that only contains characters A-Z, digits and `_`.'
    );
    return await askForRuleName();
  }

  return ruleName;
}

/**
 * @returns {Promise<RuleType | null>}
 */
async function askForRuleType() {
  let canceled = false;
  /** @type {{ruleType: RuleType}} */
  const {ruleType} = await prompts(
    {
      type: 'select',
      name: 'ruleType',
      message: `Choose the type of rule you want to start with:`,
      hint: `You can always switch the type later manually`,
      choices: [
        {
          title: 'Module rule',
          value: /** @satisfies {RuleType} */ ('module'),
          description: 'Simpler, but looks at modules in isolation'
        },
        {
          title: 'Project rule',
          value: /** @satisfies {RuleType} */ ('project'),
          description: 'More complex, but can access a lot more information'
        }
      ],
      initial: 0
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

  return ruleType;
}

/**
 * @param {string} dir
 * @param {string} fileName
 * @param {string} content
 * @returns {void}
 */
function writeFile(dir, fileName, content) {
  fs.writeFileSync(path.join(dir, fileName), content);
}

/**
 * @param {ReviewOptions} options
 * @param {PackageElmJson} elmJson
 * @param {string} ruleName
 * @param {RuleType} ruleType
 * @returns {Promise<void>}
 */
async function addRule(options, elmJson, ruleName, ruleType) {
  const ruleNameFolder = ruleName.split('.').slice(0, -1).join('/');
  const dir = path.dirname(options.elmJsonPath);

  try {
    await FS.mkdirp(path.join(dir, 'src', ruleNameFolder));
  } catch {}

  try {
    await FS.mkdirp(path.join(dir, 'tests', ruleNameFolder));
  } catch {}

  console.log(`Adding rule - ${ruleName}`);

  writeFile(
    dir,
    path.join('src', `${ruleName.split('.').join('/')}.elm`),
    newSourceFile(elmJson.name, ruleName, ruleType)
  );
  writeFile(
    dir,
    path.join('tests', `${ruleName.split('.').join('/')}Test.elm`),
    newTestFile(ruleName)
  );

  if (elmJson.type === 'package' && packageNameRegex.test(elmJson.name)) {
    console.log('Exposing the rule in elm.json');

    const exposedModules = Array.isArray(elmJson['exposed-modules'])
      ? elmJson['exposed-modules']
      : Object.values(elmJson['exposed-modules']).reduce((acc, items) => [
          ...acc,
          ...items
        ]);

    if (!exposedModules.includes(ruleName)) {
      const newElmJson = {
        ...elmJson,
        'exposed-modules': [...exposedModules, ruleName].sort()
      };

      writeFile(dir, 'elm.json', JSON.stringify(newElmJson, null, 4));

      console.log('Adding rule to the README');
    }

    try {
      const readmeContent = await FS.readFile(path.join(dir, 'README.md'), {
        encoding: 'utf8'
      });
      injectRuleInReadme(dir, elmJson, ruleName, readmeContent);
    } catch {
      console.log(
        `${chalk.red('[WARNING]')} Could not find a ${chalk.yellow(
          'README.md'
        )}`
      );
    }
  }

  const globbed = await glob('preview*/**/elm.json', {
    caseSensitiveMatch: false,
    ignore: ['**/elm-stuff/**'],
    cwd: dir,
    absolute: true
  });

  // Inject configuration into every preview configuration
  for (const configurationElmJson of globbed) {
    injectRuleInPreview(path.dirname(configurationElmJson), elmJson, ruleName);
  }
}

/**
 * @param {string} dir
 * @param {PackageElmJson} elmJson
 * @param {string} ruleName
 * @returns {void}
 */
function injectRuleInPreview(dir, elmJson, ruleName) {
  try {
    const content = fs.readFileSync(
      path.join(dir, 'src/ReviewConfig.elm'),
      'utf8'
    );
    const lines = content.split('\n');
    insertRuleInConfiguration(dir, elmJson, ruleName, lines);
    writeFile(dir, 'src/ReviewConfig.elm', lines.join('\n'));
  } catch {
    console.log(
      `${chalk.red('[WARNING]')} Could not find ${chalk.yellow(
        path.join(dir, 'src/ReviewConfig.elm')
      )}`
    );
  }
}

/**
 * @param {string} dir
 * @param {PackageElmJson} elmJson
 * @param {string} ruleName
 * @param {string} content
 * @returns {void}
 */
function injectRuleInReadme(dir, elmJson, ruleName, content) {
  const lines = content.split('\n');
  insertRuleDescription(elmJson, ruleName, lines);
  insertRuleInConfiguration(dir, elmJson, ruleName, lines);
  writeFile(dir, 'README.md', lines.join('\n'));
}

const ruleSectionRegex = /^#+.*rules/i;

/**
 * @remarks
 * Mutates `lines`!
 *
 * @param {PackageElmJson} elmJson
 * @param {string} ruleName
 * @param {string[]} lines
 * @returns {void}
 */
function insertRuleDescription(elmJson, ruleName, lines) {
  const rulesSectionIndex = lines.findIndex((line) =>
    ruleSectionRegex.test(line)
  );

  if (rulesSectionIndex) {
    if (!alreadyHasRuleDescription(ruleName, rulesSectionIndex, lines)) {
      const description = ruleDescription(
        elmJson.name,
        elmJson.version,
        ruleName
      );
      lines.splice(rulesSectionIndex + 2, 0, description);
    }
  } else {
    console.log(
      `${chalk.red('[WARNING]')} Could not find a ${chalk.yellow(
        'Provided rules'
      )} section in README to include the rule in`
    );
  }
}

/**
 * @param {string} ruleName
 * @param {number} rulesSectionIndex
 * @param {string[]} lines
 * @returns {boolean}
 */
function alreadyHasRuleDescription(ruleName, rulesSectionIndex, lines) {
  const nextSectionIndex = findNextSectionIndex(rulesSectionIndex, lines);

  const textBlock = lines.slice(rulesSectionIndex, nextSectionIndex).join('\n');

  return textBlock.includes(
    `- [\`${ruleName}\`](https://package.elm-lang.org/packages`
  );
}

/**
 * @param {number} previousSectionIndex
 * @param {string[]} lines
 * @returns {number}
 */
function findNextSectionIndex(previousSectionIndex, lines) {
  const nextSectionIndex = lines
    .slice(previousSectionIndex + 1)
    .findIndex((line) => /^#+/.test(line));

  if (nextSectionIndex === -1) {
    return lines.length;
  }

  return previousSectionIndex + nextSectionIndex + 1;
}

/**
 * @remarks
 * Mutates `lines`!
 *
 * @param {string} configurationPath
 * @param {PackageElmJson} elmJson
 * @param {string} ruleName
 * @param {string[]} lines
 * @returns {void}
 */
function insertRuleInConfiguration(
  configurationPath,
  elmJson,
  ruleName,
  lines
) {
  if (lines.join('\n').includes(`import ${ruleName}\n`)) {
    // Rule already exists in configuration
    return;
  }

  const someOtherRule = /** @type {string[]} */ (elmJson['exposed-modules'])[0];
  insertImport(configurationPath, ruleName, lines);
  insertRuleInConfigList(ruleName, someOtherRule, lines);
}

/**
 * @param {string} configurationPath
 * @param {string} ruleName
 * @param {string[]} lines
 * @returns {void}
 */
function insertImport(configurationPath, ruleName, lines) {
  const firstImportIndex = lines.findIndex((line) => line.startsWith('import'));

  if (firstImportIndex === -1) {
    console.log(
      `${chalk.red(
        '[WARNING]'
      )} Could not find where to add an import of the rule in the ${configurationPath} configuration`
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

/**
 * @param {string} ruleName
 * @param {string} someOtherRule
 * @param {string[]} lines
 * @returns {void}
 */
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

/**
 * @param {string} fullPackageName
 * @param {string} ruleName
 * @param {RuleType} ruleType
 * @returns {string}
 */
function newSourceFile(fullPackageName, ruleName, ruleType) {
  return `module ${ruleName} exposing (rule)

{-|

@docs rule

-}

import Elm.Syntax.Expression exposing (Expression)
import Elm.Syntax.Node as Node exposing (Node)
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
This rule is not useful when REPLACEME.


## Try it out

You can try this rule out by running the following command:

\`\`\`bash
elm-review --template ${fullPackageName}/example --rules ${ruleName}
\`\`\`

-}
${
  ruleType === 'project'
    ? projectRuleTemplate(ruleName)
    : moduleRuleTemplate(ruleName)
}`;
}

/**
 * @param {string} ruleName
 * @returns {string}
 */
function moduleRuleTemplate(ruleName) {
  return `rule : Rule
rule =
    Rule.newModuleRuleSchemaUsingContextCreator "${ruleName}" initialContext
        |> Rule.withExpressionEnterVisitor expressionVisitor
        |> Rule.fromModuleRuleSchema


type alias Context =
    {}


initialContext : Rule.ContextCreator () Context
initialContext =
    Rule.initContextCreator
        (\\() ->
            {}
        )


expressionVisitor : Node Expression -> Context -> ( List (Rule.Error {}), Context )
expressionVisitor node context =
    case Node.value node of
        _ ->
            ( [], context )
`;
}

/**
 * @param {string} ruleName
 * @returns {string}
 */
// TODO(@lishaduck): Create a branded `ElmSource` type.
function projectRuleTemplate(ruleName) {
  return `rule : Rule
rule =
    Rule.newProjectRuleSchema "${ruleName}" initialProjectContext
        |> Rule.withModuleVisitor moduleVisitor
        |> Rule.withModuleContextUsingContextCreator
            { fromProjectToModule = fromProjectToModule
            , fromModuleToProject = fromModuleToProject
            , foldProjectContexts = foldProjectContexts
            }
        -- Enable this if modules need to get information from other modules
        -- |> Rule.withContextFromImportedModules
        |> Rule.fromProjectRuleSchema


type alias ProjectContext =
    {}


type alias ModuleContext =
    {}


moduleVisitor : Rule.ModuleRuleSchema schema ModuleContext -> Rule.ModuleRuleSchema { schema | hasAtLeastOneVisitor : () } ModuleContext
moduleVisitor schema =
    schema
        |> Rule.withExpressionEnterVisitor expressionVisitor


initialProjectContext : ProjectContext
initialProjectContext =
    {}


fromProjectToModule : Rule.ContextCreator ProjectContext ModuleContext
fromProjectToModule =
    Rule.initContextCreator
        (\\projectContext ->
            {}
        )


fromModuleToProject : Rule.ContextCreator ModuleContext ProjectContext
fromModuleToProject =
    Rule.initContextCreator
        (\\moduleContext ->
            {}
        )


foldProjectContexts : ProjectContext -> ProjectContext -> ProjectContext
foldProjectContexts new previous =
    {}


expressionVisitor : Node Expression -> ModuleContext -> ( List (Rule.Error {}), ModuleContext )
expressionVisitor node context =
    case Node.value node of
        _ ->
            ( [], context )
`;
}

/**
 * @param {string} ruleName
 * @returns {string}
 */
function newTestFile(ruleName) {
  return `module ${ruleName}Test exposing (all)

import ${ruleName} exposing (rule)
import Review.Test
import Test exposing (Test, describe, test)


all : Test
all =
    describe "${ruleName}"
        [ test "should not report an error when REPLACEME" <|
            \\() ->
                """module A exposing (..)
a = 1
"""
                    |> Review.Test.run rule
                    |> Review.Test.expectNoErrors
        , test "should report an error when REPLACEME" <|
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

/**
 * @param {string} packageName
 * @param {string} packageVersion
 * @param {string} ruleName
 * @returns {string}
 */
function ruleDescription(packageName, packageVersion, ruleName) {
  const ruleNameAsUrl = ruleName.split('.').join('-');
  return `- [\`${ruleName}\`](https://package.elm-lang.org/packages/${packageName}/${packageVersion}/${ruleNameAsUrl}) - Reports REPLACEME.`;
}

module.exports = {
  create,
  askForRuleName,
  askForRuleType,
  newSourceFile,
  newTestFile,
  ruleDescription,
  validateRuleName
};

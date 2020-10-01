# Tooling integration

This is information dedicated to people who want to use the `elm-review` CLI in a different
environment than a user's terminal, like editors or GitHub actions.

## The name

The name of the project is `elm-review`, not Elm Review.

## Things I expect you to do

### Namespacing

If it is possible for your tool to run at the same time as an unrelated `elm-review` CLI run (e.g. an editor), then I'd like you to spawn the CLI using the `--namespace <unique-name-for-your-tool>` (please don't make it look like a semantic version number, to facilitate removing this later on if it happens to be a bad idea).

The CLI creates a bunch of cache inside `elm-stuff/generated-code/jfmengels/elm-review/<namespace>/<CLI version>/` with `cli` as the default `namespace`, including
- `file-cache/`: Caching of the file's ASTs.
- `review-applications/`: Caching of the project's configuration. This is the application we build by compiling the source code in the CLI's `template/` directory.
- `dependencies-cache/`: Caching of the dependencies of the project's configuration computed by `elm-json`. `elm-json` is a bit slow, and doesn't work great offline. This is done so we don't have to compute the dependencies again if the configuration changed but not `review/elm.json`.

Namespacing things means that data will unfortunately be duplicated, but it is meant to prevent different tools from stepping on each other's toes by saving the same files at the same time as another, potentially corrupting the files.

### Provide the path to the Elm compiler and to elm-format

If you happen to know the path to these two executables, please run using
  - `--compiler <path-to-elm>`
  - `--elm-format-path <path-to-elm-format>`. `elm-format` is used to re-format files after they have been fixed (`--fix` or `--fix-all`). If you are not running that, you have no need to specify `--elm-format-path`. As you will see in a different section below, the JSON format will give you the necessary steps to perform a fix yourself.

This will help the CLI by not trying several paths before succeeding. If you don't specify these, this is how the binaries are found:
  - `elm`: We run `which elm` and use that path.
  - `elm-format`: We run `npx --no-install elm-format`, and fallback to a `elm-format`.

If you are unsure that these paths are correct, then maybe omit these, as the CLI
will not attempt to fallback to other paths.

## Format of the JSON

If you desire to get the output of the CLI as JSON, you can run with `--report=json`. This flag became available in version `2.1.0` of the CLI, which in turns requires version `2.1.0 <= x < 3.0.0` of the `jfmengels/elm-review` package. The output of this report is detailed below.

### Review errors

If the process ran without any hitches, you should get something like the following:

```json
{
  "type": "review-errors",
  "errors": [
    {
      "path": "src/Some/File.elm",
      "errors": [
        {
          "rule": "NoUnused.Variables",
          "ruleLink": "https://package.elm-lang.org/packages/jfmengels/elm-review-unused/1.0.1/NoUnused-Variables",
          "message": "Top-level variable `unusedVariable` is not used",
          "details": [
            "You should either use this value somewhere, or remove it at the location I pointed at."
          ],
          "region": {
            "start": {
              "line": 49,
              "column": 1
            },
            "end": {
              "line": 49,
              "column": 15
            }
          },
          "fix": [
            {
              "range": {
                "start": {
                  "line": 49,
                  "column": 1
                },
                "end": {
                  "line": 51,
                  "column": 1
                }
              },
              "string": ""
            }
          ],
          "formatted": [
            {
              "string": "(fix) ",
              "color": "#33BBC8"
            },
            {
              "string": "NoUnused.Variables",
              "color": "#FF0000"
            },
            ": Top-level variable `unusedVariable` is not used\n\n49| unusedVariable =\n    ",
            {
              "string": "^^^^^^^^^^^^^^",
              "color": "#FF0000"
            },
            "\n50|      1\n\nYou should either use this value somewhere, or remove it at the location I pointed at."
          ]
        }
      ]
    }
  ]
}
```

- `type`: Equal to `"review-errors"` when the run went well (finding errors or not)
- `errors`: The array of errors that `elm-review` found. If it is empty, then no errors were found (in a normal run, `elm-review` would then exit with status code 0). The following describe each item in the array.
  - `path`: The relative path to the file for which the (sibling) errors are reported.
  - `errors`: ("single-error") The array of errors that `elm-review` found for this file. The following describe each item in the array.
    - `rule`: The name of the rule that reported this error.
    - `ruleLink` (optional): **(Since 2.1.2)** The link to the rule's documentation on the Elm package website, if the rule is not a local one.
    - `message`: A short description of the error. If you show a summary of the errors, this is what you will want to show, along with `rule`.
    - `details`: A longer description, providing more details about the error and often a description of how to resolve it. Every string in this array of strings corresponds to a paragraph.
    - `region`: The region in which this error occurred. The `line` and `column` values start from `1`, not `0`.
    - `fix` (optional): A list of fixes/edits to automatically solve the errors. Each "edit" describes a range (1-based) in the source code to replace, and what to replace it by. If `string` is empty, it means we are removing code, if the `start` and `end` are the same, we are inserting code, otherwise we are modifying code.
    In the CLI, these are applied one-by-one, starting from the ones that are near the end of the file. When applying them, the CLI makes sure that there are no overlapping ranges and that the fix results in an Elm file without syntax errors. These are all steps that you need to do yourself at the moment.
    (Proposal to be discussed: maybe the CLI can be spawned with this fix data and apply its own algorithm, to avoid you having to do all this work?)
    - `formatted`: An array of "chunks" that represent the full human-readable error that would be shown to the user. Chunks are described [below](#chunk).

### Newline delimited JSON

Alternatively, you can use `--report=ndson` to print each review error on its own line. The report is a list of `"single-error"` (as described above) delimited by a new line, except that the `path` field was added so that information does not become lost.

This can be useful to send `elm-review` errors to logging/monitoring services.

```
{"path":"src/Main.elm","rule":"NoUnused.Variables","message":"Imported variable `span` is not used","ruleLink":"https://package.elm-lang.org/packages/jfmengels/review-unused/2.1.3/NoUnused-Variables","details":["You should either use this value somewhere, or remove it at the location I pointed at."],"region":{"start":{"line":10,"column":11},"end":{"line":10,"column":15}},"fix":[{"range":{"start":{"line":8,"column":14},"end":{"line":10,"column":15}},"string":""}],"formatted":[{"string":"(fix) ","color":"#33BBC8"},{"string":"NoUnused.Variables","color":"#FF0000","href":"https://package.elm-lang.org/packages/jfmengels/review-unused/2.1.3/NoUnused-Variables"},": Imported variable `span` is not used\n\n 9|           -- span is unused\n10|         , span\n             ",{"string":"^^^^","color":"#FF0000"},"\n11|         , text\n\nYou should either use this value somewhere, or remove it at the location I pointed at."]}
{"path":"src/Main.elm","rule":"NoUnused.CustomTypeConstructors","message":"Type constructor `UnusedCustomType` is not used.","ruleLink":"https://package.elm-lang.org/packages/jfmengels/review-unused/2.1.3/NoUnused-CustomTypeConstructors","details":["This type constructor is never used. It might be handled everywhere it might appear, but there is no location where this value actually gets created."],"region":{"start":{"line":28,"column":7},"end":{"line":28,"column":23}},"formatted":["",{"string":"NoUnused.CustomTypeConstructors","color":"#FF0000","href":"https://package.elm-lang.org/packages/jfmengels/review-unused/2.1.3/NoUnused-CustomTypeConstructors"},": Type constructor `UnusedCustomType` is not used.\n\n27|     | Decrement\n28|     | UnusedCustomType\n          ",{"string":"^^^^^^^^^^^^^^^^","color":"#FF0000"},"\n\nThis type constructor is never used. It might be handled everywhere it might appear, but there is no location where this value actually gets created."]}
```


#### Chunk

A chunk represents a (un)stylized piece of the full human-readable error that would be shown to the user. It can be either a simple string, in which case there is no special formatting, or it can be an object with several optional fields::
  - `string`: The string to display
  - `color` (optional): Represents the color of the string, as a hex color string (`#33BBC8"`) or as a named color (`red`, `YELLOW`).
  - `href` (optional): A URL link.
  - `bold` (optional): If true, then the string should appear bold.
  - `underline` (optional): If true, then the string should be underlined.


That is it at the moment, but  fields like `bold` will appear later. If you fail to understand/decode the field, it is probably best to ignore it and just display the string without styling and to report an issue.


### CLI errors

Everything doesn't always go as planned, and sometimes we run into problems we anticipated and others that we didn't.
In that case, we (should) still report errors as JSON, with the following format:

```json
{
  "type": "error",
  "title": "COULD NOT FIND ELM.JSON",
  "path": "elm.json",
  "message": "I was expecting to find an elm.json file in the current directory or one of its parents, but I did not find one.\n\nIf you wish to run elm-review from outside your project,\ntry re-running it with --elmjson <path-to-elm.json>.",
  "stack": "Error: I was expecting to find an elm.json file in the current directory or one of its parents, but I did not find one.\n\nIf you wish to run elm-review from outside your project,\ntry re-running it with --elmjson <path-to-elm.json>.\n    at Object.projectToReview (/home/jeroen/dev/node-elm-review/lib/options.js:46:13)\n    at Object.build (/home/jeroen/dev/node-elm-review/lib/build.js:42:35)\n    at runElmReview (/home/jeroen/dev/node-elm-review/lib/main.js:62:41)\n    at module.exports (/home/jeroen/dev/node-elm-review/lib/main.js:105:3)\n    at Object.<anonymous> (/home/jeroen/dev/node-elm-review/bin/elm-review:3:23)\n    at Module._compile (internal/modules/cjs/loader.js:1144:30)\n    at Object.Module._extensions..js (internal/modules/cjs/loader.js:1164:10)\n    at Module.load (internal/modules/cjs/loader.js:993:32)\n    at Function.Module._load (internal/modules/cjs/loader.js:892:14)\n    at Function.executeUserEntryPoint [as runMain] (internal/modules/run_main.js:71:12)"
}
```

- `type`: Equal to `"error"` when things are unexpected
- `path`: The relative path to a file we could trace the problem to, or to a default one. This is in a lot of cases using a default value, because we are not able to pinpoint to a specific file. Also the default file might not exist, which may be the cause of the error.
- `message`: The description of the problem. It is an array like `formatted` for review errors, even though at this moment it only contains a string that has been trimmed and where colors have been removed.
- `stack` (optional): The original JavaScript runtime stacktrace. Only sent if you run with `--debug`.

You should only have to listen to the CLI's standard output (`stdout`), and should not have to listen to the standard error output (`stderr`).

## Things that may help you

Running with `--debug` will:
- Add the stack trace when you run into an (un)expected error while running the CLI
- Pretty print the JSON output, and add the stack trace to it.

If you run into trouble, you can safely delete the `elm-stuff/generated-code/jfmengels/elm-review` directory.

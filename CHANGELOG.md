# Changelog

## [Unreleased]

## [2.13.1] - 2025-02-13

- Fixed an issue causing fix diff proposals not to be properly indented.
- Improve the error message when getting rate limit errors from GitHub after using `--template` too often.
- Only require the personal access token (and not the username + personal access token) when using `--github-auth` (to prevent GitHub rate limits).
- Improved performance around listing files to load.
- Removed dependency `glob`.

## [2.13.0] - 2025-02-11

Now requires `jfmengels/elm-review` v2.15.0, as well as Node.js 14 and newer.

- Added support for multi-file fixes and file removals introduced in the Elm package (see its [CHANGELOG](https://github.com/jfmengels/elm-review/blob/main/CHANGELOG.md#2150---2025-02-11)).
- Added `--allow-remove-files` to enable file removal in fixes
- Improved the output of the error report.
- Added `--explain-fix-failure` to get more information about why an automatic fix failed.
- Publicly documented the `--fix-all-without-prompt` CLI flag. Please use it well!
- The `--compiler` flag now additionally resolves the compiler path using the `PATH` environment variable (more easily enabling `elm-review --compiler lamdera` for instance).
- The `--elm-format-path` flag now additionally resolves the path to `elm-format` using the `PATH` environment variable.
- Fixed an issue where the initial rule created with `elm-review new-package` was always a module rule, even when it was requested to be a project rule. Thanks to [@mateusfpleite](https://github.com/mateusfpleite)!
- Fixed an issue where files in source-directories under `elm-stuff/` would not be included in the analysis.
- Fixed an issue where colors would not show up.
- Plenty of behind the scenes improvement to the maintenance of the repository. Thanks to [@lishaduck](https://github.com/lishaduck) for all of those.
- Optimized the usages of `>>` and `<<` used in the Elm code to be run.

## [2.12.0] - 2024-06-14

Now requires `jfmengels/elm-review` v2.14.0.

- Now supports analyzing arbitrary files that the project doesn't analyze by default.

## [2.11.2] - 2024-05-03

- The `--ignore-dirs` and `--ignore-files` flags now support absolute paths. Thanks [@jamesrweb](https://github.com/jamesrweb)!
- Fixed an issue where the CLI output would sometimes be cut off abruptly. Thanks [@BrianHicks](https://github.com/BrianHicks)!
- When using `--watch` and `--report=json`, reviews will now be triggered when files are changed even when the contents are triggered, to make it easier for editors to integrate `elm-review`.

## [2.11.1] - 2024-03-16

- Fixed a crash when running in watch mode related to not being able to fetch cache results.
- Improve the error message when failing to update suppression files.

## [2.11.0] - 2024-03-15

- Add an `offline` mode to prevent `elm-review` from making any HTTP requests. This is useful for CI environments that should not have access to the internet, where you only want to run `elm-review` without arguments.
- Introduce `prepare-offline` subcommand to have `elm-review` fetch and pre-build all the necessary data when it has network access to prepare for being run using `elm-review --offline`.
- Replaced the internally used `elm-json` dependency with `elm-solve-deps-wasm`, which should be more reliable, re-enable support for old MacOS versions as well as improve performance.
- Fixed a crash when using `--template` from the same repository but from two different paths.
- Fixed an issue where project rules created using `elm-review new-rule` mixed the `ModuleContext` and `ProjectContext`.

## [2.10.3] - 2023-09-26

- Fixed crash when too many errors were reported.
- Improved guidance after using `elm-review init --template <some-template>`.

## [2.10.2] - 2023-05-05

Replace some npm dependencies.

## [2.10.1] - 2023-04-19

Improved error message when the version of the `jfmengels/elm-review` Elm package is not supported.

## [2.10.0] - 2023-04-16

Now requires `jfmengels/elm-review` v2.13.0.

- Fixes are now no longer applied in the CLI, but are entirely handled by the `jfmengels/elm-review` package.
  This should improve some incorrect behavior where fixes were not applied as expected.
- Re-organization of how fixes to `elm.json` are handled in autofix mode.

## [2.9.2] - 2023-03-21

`elm-review new-rule` now creates a more helpful starting rule. It can also generate a project rule if you think that
you will need that. This change also applies to the rule created using `elm-review new-package`.

Bug fixes:

- Fix watch issue on Windows by [@bdukes](https://github.com/bdukes) [#107]

## [2.9.1] - 2022-12-20

Optimizes the internal stringification of project contexts. Hopefully this will improve performance, but it's mostly useful to avoid stack overflows during that process.

## [2.9.0] - 2022-12-18

Now requires `jfmengels/elm-review` v2.11.0.

- Adds a file-system cache for the linting results, which improves performance by quite a bit.
- Improve the error message when indicated that the package version is not supported
- Fix a problem where in watch and fix mode, the CLI sometimes remained stuck.

## [2.8.4] - 2022-12-02

- Fix incorrect reports in `--watch` mode

## [2.8.3] - 2022-12-01

- Document the `--debug` flag better in `--help`
- Document the `--extract` flag better in `--help`
- Document the `--benchmark-info` flag in `--help`
- Give a more helpful error when using an outdated version of the package
- Fix a crash when running with `--fix` in non-TTY mode (in CI for instance)

## [2.8.2] - 2022-11-09

The `tests/` folder at the root of the project is now included in the tests folder to look for.

## [2.8.0] / [2.8.1] - 2022-11-08

(A technical mishap caused 2.8.0 to not be publishable, so this is technically only 2.8.1)

Now requires `jfmengels/elm-review` v2.10.0.

This release is partially announced by [this announcement blog post](https://jfmengels.net/much-faster-fixes/).

- By using the package's new way of handling fixes, fixes have become much faster
- Introduce `--fix-limit=N` flag to limit the number of fixes to apply before prompting the user
- Introduce `--extract` to extract data from the project (needs to be run with `--report=json`)
- Include the information of how long a rule ran for when running with `--benchmark-info`
- More tests folders are now included. Before, `elm-review` looked at the source-directories plus the `tests/` folder in the root of the Elm project.
  Instead, `elm-review` will now look for a `tests/` folder next to every source-directory. This should accommodate projects with multiple Elm subprojects.

## [2.7.6] - 2022-10-12

Updated the packages created by `elm-review new-package` to

- use `elm-explorations/test` v2
- include [`NoConfusingPrefixOperator`](https://package.elm-lang.org/packages/jfmengels/elm-review-common/latest/NoConfusingPrefixOperator) in the default `ReviewConfig`.

## [2.7.5] - 2022-09-10

- Fixed an issue where `elm-review init --template ...` could sometimes crash if the project already had a review configuration
- Updated the GitHub Actions workflow so that the project always runs on the latest LTS version of Node

## [2.7.4] - 2022-08-21

- Fixed an issue on Windows where suppressed didn't work [#80]
- Improved the error message when a source-directory in the review configuration's `elm.json` is unknown (fixes [#79])
- Changed the error message for suppressed error messages to be nicer
- Documented the `--no-color` flag, and forced colors to be enabled so that `elm-review`'s output stays colored when piped to commands like `less`
  - Please report an issue if this causes problems for you

## [2.7.3] - 2022-07-13

- Bump dependency `got` to a version that does not contain known security vulnerabilities
- Show dedicated error message when running `elm-review --suppress` instead of `elm-review suppress`
- Improved error message when using an unknown flag
- Added colors to the output of `elm-review suppress`
- Fixed issue where fix proposals were unnecessarily indented

## [2.7.2] - 2022-04-26

- Added mentions of `elm-review` starter configurations

## Missing changelog

Help would be appreciated to fill the blanks!

[Unreleased]: https://github.com/jfmengels/node-elm-review/compare/v2.13.1...HEAD
[2.13.1]: https://github.com/jfmengels/node-elm-review/releases/tag/2.13.1
[2.13.0]: https://github.com/jfmengels/node-elm-review/releases/tag/2.13.0
[2.12.0]: https://github.com/jfmengels/node-elm-review/releases/tag/2.12.0
[2.11.2]: https://github.com/jfmengels/node-elm-review/releases/tag/2.11.2
[2.11.1]: https://github.com/jfmengels/node-elm-review/releases/tag/2.11.1
[2.11.0]: https://github.com/jfmengels/node-elm-review/releases/tag/2.11.0
[2.10.3]: https://github.com/jfmengels/node-elm-review/releases/tag/2.10.3
[2.10.2]: https://github.com/jfmengels/node-elm-review/releases/tag/2.10.2
[2.10.1]: https://github.com/jfmengels/node-elm-review/releases/tag/2.10.1
[2.10.0]: https://github.com/jfmengels/node-elm-review/releases/tag/2.10.0
[2.9.1]: https://github.com/jfmengels/node-elm-review/releases/tag/2.9.1
[2.9.0]: https://github.com/jfmengels/node-elm-review/releases/tag/2.9.0
[2.8.4]: https://github.com/jfmengels/node-elm-review/releases/tag/2.8.4
[2.8.3]: https://github.com/jfmengels/node-elm-review/releases/tag/2.8.3
[2.8.2]: https://github.com/jfmengels/node-elm-review/releases/tag/2.8.2
[2.8.1]: https://github.com/jfmengels/node-elm-review/releases/tag/2.8.1
[2.8.0]: https://github.com/jfmengels/node-elm-review/releases/tag/2.8.0
[2.7.6]: https://github.com/jfmengels/node-elm-review/releases/tag/2.7.6
[2.7.5]: https://github.com/jfmengels/node-elm-review/releases/tag/2.7.5
[2.7.4]: https://github.com/jfmengels/node-elm-review/releases/tag/2.7.4
[2.7.3]: https://github.com/jfmengels/node-elm-review/releases/tag/2.7.3
[2.7.2]: https://github.com/jfmengels/node-elm-review/releases/tag/2.7.2
[#107]: https://github.com/jfmengels/node-elm-review/pull/107
[#80]: https://github.com/jfmengels/node-elm-review/pull/80
[#79]: https://github.com/jfmengels/node-elm-review/issue/79

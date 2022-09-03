# Changelog

## UNRELEASED

- Fixed an issue where `elm-review init --template ...` could sometimes crash if the project already had a review configuration.

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

[2.7.4]: https://github.com/jfmengels/node-elm-review/releases/tag/2.7.4
[2.7.3]: https://github.com/jfmengels/node-elm-review/releases/tag/2.7.3
[2.7.2]: https://github.com/jfmengels/node-elm-review/releases/tag/2.7.2

[#80]: https://github.com/jfmengels/node-elm-review/pull/80
[#79]: https://github.com/jfmengels/node-elm-review/issue/79

[9bdc37b98c5e29f00e9485cf78bce0a3ff715761]: https://github.com/jfmengels/node-elm-review/commit/9bdc37b98c5e29f00e9485cf78bce0a3ff715761

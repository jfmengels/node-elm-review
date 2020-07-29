# elm-review-something

Provides [`elm-review`](https://package.elm-lang.org/packages/jfmengels/elm-review/latest/) rules to REPLACEME.


## Provided rules

- [`SomeRule`](https://package.elm-lang.org/packages/some-author/elm-review-something/1.0.0/SomeRule) - Reports REPLACEME.
- [`No.Doing.Foo`](https://package.elm-lang.org/packages/some-author/elm-review-something/1.0.0/No-Doing-Foo) - Reports REPLACEME.


## Configuration

```elm
module ReviewConfig exposing (config)

import No.Doing.Foo
import Review.Rule exposing (Rule)
import SomeRule

config : List Rule
config =
    [ No.Doing.Foo.rule
    , SomeRule.rule
    ]
```

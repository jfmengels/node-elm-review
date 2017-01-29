# node-elm-lint

Run [elm-lint](https://github.com/jfmengels/elm-lint) from Node.js.

## Installation

```bash
npm install -g elm-lint
```

## Usage

```bash
elm-test init  # Adds the elm-test dependency and creates Main.elm and Tests.elm
elm-test       # Runs the tests
```

Then add your tests to Tests.elm.


### Configuration

The `--compiler` flag can be used to use a version of the Elm compiler that
has not been installed globally.

```
npm install elm
elm-test --compiler ./node_modules/.bin/elm-make
```


### Travis CI

If you want to run your tests on Travis CI, here's a good starter `.travis.yml`:

```yml
sudo: false

cache:
  directories:
    - elm-stuff/build-artifacts
    - elm-stuff/packages
    - sysconfcpus
os:
  - linux

env:
  matrix:
    - ELM_VERSION=0.18.0 TARGET_NODE_VERSION=node

before_install:
  - echo -e "Host github.com\n\tStrictHostKeyChecking no\n" >> ~/.ssh/config

install:
  - nvm install $TARGET_NODE_VERSION
  - nvm use $TARGET_NODE_VERSION
  - node --version
  - npm --version
  - npm install -g elm@$ELM_VERSION elm-test
  - git clone https://github.com/NoRedInk/elm-ops-tooling
  - elm-ops-tooling/with_retry.rb elm package install --yes
  # Faster compile on Travis.
  - |
    if [ ! -d sysconfcpus/bin ];
    then
      git clone https://github.com/obmarg/libsysconfcpus.git;
      cd libsysconfcpus;
      ./configure --prefix=$TRAVIS_BUILD_DIR/sysconfcpus;
      make && make install;
      cd ..;
    fi
before_script:
  - $TRAVIS_BUILD_DIR/sysconfcpus/bin/sysconfcpus -n 2 elm-make ./tests/Main.elm

script:
  - elm-test ./tests/Main.elm

```

### Doc-Tests

You can use `elm-test` to run your [doc-tests][1].
This uses [`elm-doc-test`][1] under the hood. See `examples` or the [README.md](https://github.com/stoeffel/elm-doc-test/blob/master/Readme.md) of [`elm-doc-test`][1].

```bash
elm-test --doctest
```

[1]: https://github.com/stoeffel/elm-doc-test

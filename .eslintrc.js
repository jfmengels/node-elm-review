module.exports = {
  root: true,
  extends: ['xo', 'prettier', 'plugin:@typescript-eslint/recommended'],
  plugins: ['node', 'unicorn', '@typescript-eslint'],
  parser: '@typescript-eslint/parser',
  env: {
    node: true
  },
  ignorePatterns: [
    '**/node_modules/',
    '**/elm-stuff/',
    'test/run-snapshots',
    'test/snapshots',
    'test/temporary',
    'vendor/node-elm-compiler.js'
  ],
  rules: {
    complexity: 'off',
    'import/extensions': 'off',
    indent: 'off',
    'comma-dangle': 'off',
    curly: 'off',
    quotes: 'off',
    'arrow-body-style': 'off',
    'prettier/prettier': 'off',
    'object-shorthand': 'off',
    'operator-linebreak': 'off',
    'max-params': 'off',
    'arrow-parens': 'off',
    'promise/prefer-await-to-then': 'off',
    'unicorn/no-fn-reference-in-iterator': 'off',
    'unicorn/no-reduce': 'off',
    'unicorn/prefer-module': 'off',
    'unicorn/prefer-node-protocol': 'off',
    '@typescript-eslint/no-var-requires': 'off'
  },
  globals: {
    test: 'readonly',
    expect: 'readonly'
  }
};
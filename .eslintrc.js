// @ts-check
// TODO(@lishaduck) [eslint@>9.5]: Use `.ts` extension to get more type checking for this file.
// TODO(@lishaduck) [engine:node@>=18]: Upgrade `tseslint`.
// TODO(@lishaduck) [engine:node@>=18]: Use `eslint-define-config` to get type checking for this file.
// TODO(@lishaduck) [engine:node@>=18]: Use `eslint-plugin-jsdoc` to get JSDoc linting.

module.exports = {
  root: true,
  extends: [
    'xo', // Should we also use eslint-config-xo-typescript?
    'turbo',
    'plugin:n/recommended',
    'plugin:security/recommended-legacy',
    'plugin:@eslint-community/eslint-comments/recommended',
    'plugin:promise/recommended',
    'plugin:unicorn/recommended',
    'plugin:@typescript-eslint/recommended-type-checked',
    'plugin:@typescript-eslint/stylistic-type-checked',
    'prettier'
  ],
  plugins: [
    'n',
    'todo-plz',
    'security',
    'promise',
    'unicorn',
    '@typescript-eslint'
  ],
  parser: '@typescript-eslint/parser',
  parserOptions: {
    // A stable, but experimental, option to speed up linting.
    // It's also more feature complete, as it relies on the TypeScript Language Service.
    EXPERIMENTAL_useProjectService: true // TODO(@lishaduck) [typescript-eslint@>=8]: Rename to `projectService`.
  },
  env: {
    node: true
  },
  ignorePatterns: [
    '**/node_modules/',
    '**/elm-stuff/',
    'test/run-snapshots',
    'test/snapshots',
    'test/temporary',
    'vendor/'
  ],
  rules: {
    // Style disagreements with XO.
    complexity: 'off',
    'import/extensions': 'off',
    indent: 'off',
    'comma-dangle': 'off',
    curly: 'off',
    quotes: 'off',
    'arrow-body-style': 'off',
    'object-shorthand': 'off',
    'operator-linebreak': 'off',
    'max-params': 'off',
    'arrow-parens': 'off',
    'no-warning-comments': 'off',
    'promise/no-nesting': 'warn',
    'promise/no-return-in-finally': 'error',
    'promise/valid-params': 'error',
    'promise/prefer-await-to-callbacks': 'warn',
    'promise/prefer-await-to-then': 'off',
    'no-return-await': 'off',
    '@typescript-eslint/return-await': ['error', 'always'],
    '@typescript-eslint/promise-function-async': 'error',
    '@typescript-eslint/no-confusing-void-expression': 'error',
    'unicorn/no-array-callback-reference': 'off',
    'unicorn/no-array-reduce': 'off',
    'unicorn/prefer-module': 'off',
    'unicorn/prefer-node-protocol': 'error',
    '@typescript-eslint/no-var-requires': 'off',
    '@typescript-eslint/no-empty-function': 'off',
    '@typescript-eslint/no-unused-vars': ['error', {argsIgnorePattern: '^_'}],
    '@typescript-eslint/switch-exhaustiveness-check': 'error',
    '@typescript-eslint/consistent-type-definitions': ['error', 'type'],
    'default-case': 'off',
    'n/shebang': 'off', // TODO(@lishaduck) [eslint-plugin-n@>=17]: Turn on 'n/hashbang'. For now, `shebang` is buggy.
    '@typescript-eslint/ban-ts-comment': [
      'warn',
      {
        'ts-expect-error': {descriptionFormat: '^\\(TS\\d+\\): .+$'},
        'ts-check': false
      }
    ],
    'unicorn/expiring-todo-comments': 'warn',
    'todo-plz/ticket-ref': [
      'warn',
      // Emulate `ban-untagged-todo` from deno_lint.
      {
        commentPattern: String.raw`(TODO|FIXME)\(@[a-zA-Z0-9_-]+\)( \[.+\])?:`,
        terms: ['TODO', 'FIXME'],
        description: 'For example: `TODO(@username): Make this awesomer.``'
      }
    ],
    '@eslint-community/eslint-comments/require-description': 'error',
    strict: ['error', 'global'],
    'unicorn/import-style': ['off'], // TODO(@lishaduck): Re-enable this once we use ESM.
    'unicorn/no-null': 'off',
    'unicorn/prevent-abbreviations': 'off',
    'unicorn/catch-error-name': ['error', {ignore: [/^err/i]}], // We use "error" for the result of `intoError` as well.
    'no-fallthrough': 'off', // TSESLint doesn't provide an alternative, and TS checks for this anyway.

    // TODO(@lishaduck): Once there are no more `any`s, start enforcing these rules.
    '@typescript-eslint/no-unsafe-assignment': 'off',
    '@typescript-eslint/no-unsafe-argument': 'off',
    '@typescript-eslint/no-unsafe-member-access': 'off',
    '@typescript-eslint/no-unsafe-return': 'off',

    // TODO(@lishaduck): Enable stricter promise rules.
    '@typescript-eslint/no-misused-promises': 'off',
    '@typescript-eslint/no-floating-promises': 'off',
    'promise/catch-or-return': 'off',
    'promise/always-return': 'off',

    // TODO(@lishaduck): Security issues that should eventually get fixed.
    'security/detect-object-injection': 'off',
    'security/detect-non-literal-fs-filename': 'off',
    'security/detect-non-literal-require': 'off',
    'security/detect-unsafe-regex': 'off', // TODO(@lishaduck): Add `eslint-plugin-regexp` and fix these issues.

    // TODO(@lishaduck): Enable rules that require newer versions of Node.js when we bump the minimum version.
    'unicorn/prefer-string-replace-all': 'off', // TODO(@lishaduck) [engine:node@>=15]: Enable this rule.
    'unicorn/prefer-at': 'off' // TODO(@lishaduck) [engine:node@>=16.6]: Enable this rule.
  },
  overrides: [
    {
      files: ['./new-package/**/*.js'],
      rules: {
        'n/no-process-exit': 'off',
        'n/no-missing-require': 'off',
        '@typescript-eslint/ban-ts-comment': 'off',
        '@typescript-eslint/unbound-method': 'off' // TODO(@lishaduck): Fix this warning. I just got confused.
      }
    },
    {
      files: ['.eslintrc.js'],
      rules: {
        camelcase: 'off',
        '@typescript-eslint/prefer-nullish-coalescing': 'off' // It's not happy with how TS is set up on this config file.
      }
    }
  ],
  globals: {
    test: 'readonly',
    expect: 'readonly'
  }
};

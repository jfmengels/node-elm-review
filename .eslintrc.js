// TODO [eslint@>9.5]: Use `.ts` extension to get more type checking for this file.
// TODO [engine:node@>=18]: Upgrade `tseslint`.
// TODO [engine:node@>=18]: Use `eslint-define-config` to get type checking for this file.
// TODO [engine:node@>=18]: Use `eslint-plugin-jsdoc` to get JSDoc linting.

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
  plugins: ['n', 'security', 'promise', 'unicorn', '@typescript-eslint'],
  parser: '@typescript-eslint/parser',
  parserOptions: {
    EXPERIMENTAL_useProjectService: true
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
    'vendor/',
    '.eslintrc.js'
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
    'unicorn/no-array-callback-reference': 'off',
    'unicorn/no-array-reduce': 'off',
    'unicorn/prefer-module': 'off',
    'unicorn/prefer-node-protocol': 'error',
    'unicorn/expiring-todo-comments': 'warn',
    '@typescript-eslint/no-var-requires': 'off',
    '@typescript-eslint/no-empty-function': 'off',
    '@typescript-eslint/no-unused-vars': ['error', {argsIgnorePattern: '^_'}],
    '@typescript-eslint/switch-exhaustiveness-check': 'error',
    '@typescript-eslint/consistent-type-definitions': ['error', 'type'],
    'default-case': 'off',
    'n/shebang': 'off', // TODO [eslint-plugin-n@>=17]: Turn on 'n/hashbang'. For now, `shebang` is buggy.
    '@eslint-community/eslint-comments/require-description': 'error',
    strict: ['error', 'global'],
    'unicorn/import-style': [
      'error',
      {
        styles: {
          chalk: {
            named: true
          }
        }
      }
    ],
    'unicorn/no-null': 'off',
    'unicorn/prevent-abbreviations': 'off',
    'no-fallthrough': 'off', // TS checks for this, and TSESLint doesn't provide an alternative.

    // TODO: Once there are no more `any`s, start enforcing these rules.
    '@typescript-eslint/no-unsafe-assignment': 'off',
    '@typescript-eslint/no-unsafe-argument': 'off',
    '@typescript-eslint/no-unsafe-member-access': 'off',
    '@typescript-eslint/no-unsafe-call': 'off',
    '@typescript-eslint/no-unsafe-return': 'off',

    // TODO: Enable stricter promise rules.
    '@typescript-eslint/no-misused-promises': 'off',
    '@typescript-eslint/no-floating-promises': 'off',
    'promise/catch-or-return': 'off',
    'promise/always-return': 'off',

    // TODO: Security issues that should eventually get fixed.
    'security/detect-object-injection': 'off',
    'security/detect-non-literal-fs-filename': 'off',
    'security/detect-non-literal-require': 'off',
    'security/detect-unsafe-regex': 'off', // TODO: Add `eslint-plugin-regexp` and fix these issues.

    // TODO: Enable rules that require newer versions of Node.js when we bump the minimum version.
    'unicorn/prefer-string-replace-all': 'off', // TODO [engine:node@>=15]: Enable this rule.
    'unicorn/prefer-at': 'off' // TODO [engine:node@>=16.6]: Enable this rule.
  },
  overrides: [
    {
      files: ['./new-package/**/*.js'],
      rules: {
        'n/no-process-exit': 'off',
        'n/no-missing-require': 'off',
        '@typescript-eslint/ban-ts-comment': 'off',
        '@typescript-eslint/unbound-method': 'off' // TODO: Fix this warning. @lishaduck just got confused.
      }
    }
  ],
  globals: {
    test: 'readonly',
    expect: 'readonly'
  }
};

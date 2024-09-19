/**
 * @import {Flags} from './types/flags';
 */
const Benchmark = require('./benchmark');
const Debug = require('./debug');

let hasWrittenThings = false;

/**
 * @param {Flags} options
 * @returns {unknown}
 */
function create(options) {
  return new Proxy(
    {},
    {
      /**
       * Get and respond to messages from the Elm application.
       *
       * @param {unknown} _
       * @param {string} rawMessage
       * @returns {null}
       */
      get(_, rawMessage) {
        const message = JSON.parse(rawMessage);
        switch (message.type) {
          case 'apply-fix': {
            const {ruleName, filePath, count} = message;
            if (options.debug) {
              Debug.log(
                `Applying a fix for ${ruleName} in ${filePath} (${count} so far)`
              );
            } else {
              if (!process.stdout.isTTY) {
                return null;
              }

              process.stdout.cursorTo(0);
              process.stdout.write(
                `Fixed ${count} issue${count > 1 ? 's' : ''} so far`
              );
              hasWrittenThings = true;
            }

            return null;
          }

          case 'timer-start': {
            Benchmark.start(options, message.metric);
            return null;
          }

          case 'timer-end': {
            if (hasWrittenThings && options.showBenchmark) {
              // Print a new line so that we don't end up with "Fix N issues so far<benchmark-result>" on the same line
              console.log();
              hasWrittenThings = false;
            }

            Benchmark.end(options, message.metric);
            return null;
          }

          default: {
            return null;
          }
        }
      },
      has(_, _key) {
        return true;
      }
    }
  );
}

module.exports = {
  create
};

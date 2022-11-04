const Debug = require('./debug');
const Benchmark = require('./benchmark');

module.exports = {
  create
};

let hasWrittenThings = false;

function create(options) {
  if (!process.stdout.isTTY) {
    return {};
  }

  return new Proxy(
    {},
    {
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
              process.stdout.cursorTo(0);
              process.stdout.write(
                `Fixed ${count} issue${count > 1 ? 's' : ''} so far`
              );
              hasWrittenThings = true;
            }

            return null;
          }

          case 'rule-start': {
            const {ruleName} = message;
            Debug.log('Started rule ' + ruleName);
            Benchmark.start(options, 'rule-' + ruleName);
            return null;
          }

          case 'rule-end': {
            if (hasWrittenThings) {
              // Print a new line so that we don't end up with "Fix N issues so far<benchmark-result>" on the same line
              console.log();
              hasWrittenThings = false;
            }

            const {ruleName} = message;
            Benchmark.end(options, 'rule-' + ruleName);
            return null;
          }

          case 'timer-start': {
            Benchmark.start(options, message.metric);
            return null;
          }

          case 'timer-end': {
            if (hasWrittenThings) {
              // Print a new line so that we don't end up with "Fix N issues so far<benchmark-result>" on the same line
              console.log();
              hasWrittenThings = false;
            }

            Benchmark.end(options, message.metric);
            return null;
          }

          default:
            return null;
        }
      },
      has(_, _key) {
        return true;
      }
    }
  );
}

const Debug = require('./debug');
const Benchmark = require('./benchmark');

module.exports = fixLogger;

function fixLogger(options) {
  if (!process.stdout.isTTY) {
    return {};
  }

  let appliedFixes = 0;

  return new Proxy(
    {},
    {
      get(_, rawMessage) {
        const message = JSON.parse(rawMessage);
        switch (message.type) {
          case 'reset': {
            process.stdout.clearLine(0);
            process.stdout.cursorTo(0);
            return;
          }

          case 'log': {
            const {done, remaining} = message;
            const total =
              Number.parseInt(done, 10) + Number.parseInt(remaining, 10);
            process.stdout.cursorTo(0);
            process.stdout.write(
              `I'm applying fixes! ${progressBar(done, total)} ${done}/${total}`
            );
            return null;
          }

          case 'apply-fix': {
            const {ruleName, filePath} = message;
            appliedFixes++;
            if (options.debug) {
              Debug.log(`Applying a fix for ${ruleName} in ${filePath} (${appliedFixes} so far)`);
            } else {
              process.stdout.cursorTo(0);
              process.stdout.write(`Fixed ${appliedFixes} issue${appliedFixes > 1 ? "s" : ""} so far`);
            }
            return null;
          }

          case 'rule-start': {
            const {ruleName} = message;
            Debug.log("Started rule " + ruleName);
            Benchmark.start(options, "rule-" + ruleName);
            return null;
          }

          case 'rule-end': {
            const {ruleName} = message;
            Benchmark.end(options,"rule-" + ruleName);
            return null;
          }

          case 'process-errors-start': {
            Benchmark.start(options, "Post-process review");
            return null;
          }

          case 'process-errors-end': {
            Benchmark.end(options,"Post-process review");
            return null;
          }

          case 'timer': {
            Benchmark.start(options, message.metric);
            return null;
          }

          case 'timer-end': {
            Benchmark.end(options,message.metric);
            return null;
          }

          default:
            return null;
        }
      },
      has(_, key) {
        return true;
      }
    }
  );
}

function progressBar(done, total) {
  if (total === 0) {
    return '';
  }

  const blocksToDraw = Math.floor((done / total) * 10);
  const filled = '▇'.repeat(blocksToDraw);
  const blank = '—'.repeat(10 - blocksToDraw);
  return `[${filled}${blank}]`;
}

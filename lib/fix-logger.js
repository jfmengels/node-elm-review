module.exports = fixLogger;

function fixLogger() {
  if (!process.stdout.isTTY) {
    return {};
  }

  return new Proxy(
    {},
    {
      get(_, key) {
        if (key === 'reset') {
          process.stdout.clearLine(0);
          process.stdout.cursorTo(0);
          return;
        }

        const [f, arg, remaining] = key.split('::');
        switch (f) {
          case 'log':
            process.stdout.cursorTo(0);
            process.stdout.write(
              `I am applying fixes, I have applied ${arg} already, and I see about ${remaining} more!`
            );
            return null;
          default:
            return null;
        }
      },
      has(_, key) {
        return key === 'reset' || key.startsWith('log::');
      }
    }
  );
}

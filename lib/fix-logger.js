module.exports = fixLogger;

function fixLogger() {
  if (!process.stdout.isTTY) {
    return {};
  }

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

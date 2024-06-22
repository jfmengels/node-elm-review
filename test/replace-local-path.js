const path = require('node:path');

let input = '';
process.stdin.on('data', (data) => {
  input += data.toString();
});
process.stdin.on('end', () => {
  process.stdout.write(
    input.split(path.dirname(__dirname)).join('<local-path>')
  );
});

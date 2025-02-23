#!/bin/node

/* eslint n/no-process-exit: "off" -- WIP */
import * as fsp from 'node:fs/promises';
import * as path from 'pathe';
import {fileURLToPath} from 'node:url';
import {glob} from 'tinyglobby';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const SNAPSHOTS = path.join(__dirname, 'run-snapshots');

const snapshotFiles = await glob('**/*.txt', {
  caseSensitiveMatch: true,
  ignore: [`**/elm-stuff/**`],
  cwd: SNAPSHOTS
});

for await (const file of snapshotFiles) {
  const filePath = path.join(SNAPSHOTS, file);
  const fileHandle = await fsp.readFile(filePath);
  const content = fileHandle.toString();
  if (content.includes('RATE LIMIT')) {
    console.error('INCORRECT SNAPSHOT\n');
    console.error('This file contains a rate limit error:\n');
    console.error(filePath);
    console.error(
      '\nThis likely means you hit a GitHub rate limit error while re-generating snapshots.'
    );
    process.exit(1);
  }
}

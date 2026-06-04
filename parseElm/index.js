#!/usr/bin/env node

const nodePath = require("node:path");
const fs = require("node:fs/promises");
const elmModule = require("./parse");

const outputFolder = "ast/";

const directory = process.argv[2] ?? process.cwd();

async function main() {
  const app = elmModule.Elm.ParseMain.init();
  app.ports.parseResult.subscribe(({path, output}) => {
    const outputPath = nodePath.join(outputFolder, path).replace(".elm", ".txt");
    fs.mkdir(nodePath.dirname(outputPath), {recursive: true})
      .catch(() => null)
      .then(() => fs.writeFile(outputPath, output));
  });

  const globber = fs.glob("**/*.elm", {cwd: directory});
  for await (const entry of globber) {
    const source = await fs.readFile(nodePath.join(directory, entry));
    app.ports.requestParsing.send({
      path: entry,
      source: source.toString()
    });
  }
}

main();

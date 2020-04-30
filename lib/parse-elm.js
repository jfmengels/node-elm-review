const elmModule = require('../build/parseElm');

const app = elmModule.Elm.ParseMain.init();

function parseElm(file) {
  return new Promise(resolve => {
    app.ports.parseResult.subscribe(handleResult);
    function handleResult(result) {
      if (result.path === file.path) {
        app.ports.parseResult.unsubscribe(handleResult);
        resolve(result.ast);
      }
    }

    app.ports.requestParsing.send(file);
  });
}

module.exports = parseElm;

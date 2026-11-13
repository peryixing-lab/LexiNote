const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.LEXI_TYPESCRIPT || '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript');

exports.loadTheme = function loadTheme(memory = new Map()) {
  const source = fs.readFileSync(path.join(__dirname, '../../../entry/src/main/ets/core/LexiTheme.ets'), 'utf8');
  const js = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  const module = { exports: {} };
  const nativeThemes = [];
  vm.runInNewContext(js, {
    module, exports: module.exports,
    require: () => ({ ThemeControl: { setDefaultTheme: theme => nativeThemes.push(theme) } }),
    AppStorage: { setOrCreate: (key, value) => memory.set(key, value), get: key => memory.get(key) }
  });
  return { ...module.exports, memory, nativeThemes };
};

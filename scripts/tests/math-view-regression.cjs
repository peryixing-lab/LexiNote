// Exercise the real component lifecycle with ArkUI's key-based ForEach reuse.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.LEXI_TYPESCRIPT || '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript');
const core = path.resolve(__dirname, '../../entry/src/main/ets/core');
const modules = new Map();
function load(name) {
  if (modules.has(name)) return modules.get(name);
  const mod = { exports: {} };
  const js = ts.transpileModule(fs.readFileSync(path.join(core, name + '.ets'), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  vm.runInThisContext('(function(require,module,exports){' + js + '\n})')(
    spec => load(spec.slice(2)), mod, mod.exports);
  modules.set(name, mod.exports);
  return mod.exports;
}
const { MarkdownEngine, LexiMarkdownInlineSpan } = load('MarkdownEngine');
const source = fs.readFileSync(path.resolve(__dirname, '../../entry/src/main/ets/components/LexiMathView.ets'), 'utf8');
const model = source.slice(source.indexOf('class LexiMathVisualSpan'), source.indexOf('/**'));
const methods = source.slice(source.indexOf('  @Prop'), source.indexOf('  build() {'))
  .replace(/@(Prop|State|StorageProp|Watch)\b(?:\([^)]*\))?\s*/g, '');
const js = ts.transpileModule(model + '\nclass Subject {\n' + methods + '\n}\nmodule.exports = Subject;', {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText;
const keyExpression = /\}, \(item: LexiMathVisualSpan\): string => ([^\n]+)\)/.exec(source);
assert.ok(keyExpression, 'use the component\'s actual ForEach key');
const keyFor = new Function('item', 'return ' + keyExpression[1]);
let requests;
const cache = { request(_context, text, display, dark, callback) { requests.push({ text, display, dark, callback }); } };
const mod = { exports: {} };
vm.runInThisContext('(function(module,MarkdownEngine,LexiMarkdownInlineSpan,LexiMathBitmapCache){' + js + '\n})')(
  mod, MarkdownEngine, LexiMarkdownInlineSpan, cache);
function subject(text, displayMode = false) {
  requests = [];
  const view = new mod.exports();
  view.sourceText = text;
  view.displayMode = displayMode;
  view.getUIContext = () => ({ getHostContext: () => ({ filesDir: '/app' }) });
  view.aboutToAppear();
  return view;
}
function keyedText() {
  let children = new Map();
  return view => {
    const next = new Map();
    for (const item of view.visualSpans) {
      const key = keyFor(item);
      assert.ok(!next.has(key), 'span keys must be unique');
      // ForEach invokes its builder only for new keys. Plain objects captured
      // by a reused child cannot switch from Span to ImageSpan on their own.
      next.set(key, children.get(key) || (item.bitmap ? { image: item.bitmap.data } : { text: item.segment.text }));
    }
    children = next;
    return [...children.values()];
  };
}
const bitmap = data => ({ width: 90, height: 24, data });
const tests = [
  ['inline formulas replace their source after asynchronous rendering', () => {
    const view = subject(String.raw`非负性：\(P(A)\ge 0\)，规范性：$P(\Omega)=1$。`);
    const render = keyedText();
    assert.equal(render(view).filter(node => node.image).length, 0);
    requests[1].callback(bitmap('omega'));
    const partial = render(view);
    assert.equal(partial.filter(node => node.image).length, 1);
    requests[0].callback(bitmap('probability'));
    const complete = render(view);
    assert.deepEqual(complete.filter(node => node.image).map(node => node.image), ['probability', 'omega']);
    assert.equal(complete[0], partial[0], 'resolving another formula preserves neighboring text');
    assert.equal(complete[3], partial[3], 'already rendered formulas keep their children');
  }],
  ['editing formulas and prose at the same offsets updates every visible span', () => {
    const view = subject('前 $x$ 后');
    const render = keyedText();
    requests[0].callback(bitmap('old-x'));
    render(view);
    view.sourceText = '新 $y$ 文';
    view.refreshMath();
    assert.deepEqual(render(view).map(node => node.text), ['新 ', 'y', ' 文']);
    requests[1].callback(bitmap('new-y'));
    assert.deepEqual(render(view), [{ text: '新 ' }, { image: 'new-y' }, { text: ' 文' }]);
  }],
  ['theme changes ignore older callbacks and replace the inline image', () => {
    const view = subject('结论 $x$');
    const render = keyedText();
    render(view);
    view.mathColorMode = 1;
    view.refreshMath();
    requests[0].callback(bitmap('stale-light'));
    assert.equal(render(view).filter(node => node.image).length, 0);
    assert.equal(requests[1].dark, true);
    requests[1].callback(bitmap('dark'));
    assert.equal(render(view)[1].image, 'dark');
  }],
  ['failed formulas retain their source while valid neighbors render', () => {
    const view = subject(String.raw`\(\frac{\) 与 $x$`);
    const render = keyedText();
    render(view);
    requests[0].callback(undefined);
    requests[1].callback(bitmap('valid'));
    assert.deepEqual(render(view), [{ text: String.raw`\frac{` }, { text: ' 与 ' }, { image: 'valid' }]);
  }],
  ['display formulas retain their layout and detached views ignore results', () => {
    const view = subject(String.raw`P(A\cup B)=P(A)+P(B)-P(AB)`, true);
    assert.equal(view.isStandaloneDisplay(), true);
    requests[0].callback(bitmap('display'));
    assert.equal(view.visualSpans[0].bitmap.data, 'display');
    view.refreshMath();
    view.aboutToDisappear();
    requests[1].callback(bitmap('late'));
    assert.equal(view.visualSpans[0].bitmap, undefined);
  }]
];
for (const [name, run] of tests) { run(); console.log('PASS ' + name); }
console.log(`${tests.length} math view regression groups passed.`);

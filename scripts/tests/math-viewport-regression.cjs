// Exercise the actual ArkTS viewport lifecycle with deterministic timers.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const ts = require(process.env.LEXI_TYPESCRIPT || '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript');
const source = fs.readFileSync(path.resolve(__dirname, '../../entry/src/main/ets/core/LexiMathViewport.ets'), 'utf8');
const js = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 } }).outputText;
let now = 0, nextTimer = 0;
const timers = new Map();
const sandbox = { exports: {}, setTimeout: (fn, delay) => { const id = ++nextTimer; timers.set(id, {fn, at: now + delay}); return id; }, clearTimeout: id => timers.delete(id) };
function advance(ms) {
  const until = now + ms;
  while (true) {
    const next = [...timers.entries()].sort((a,b) => a[1].at - b[1].at)[0];
    if (!next || next[1].at > until) break;
    now = next[1].at; timers.delete(next[0]); next[1].fn();
  }
  now = until;
}
vm.runInNewContext(js, sandbox);
const Viewport = sandbox.exports.LexiMathViewport;
let mounts = 0, unmounts = 0;
const views = Array.from({length: 500}, () => new Viewport(() => mounts++, () => unmounts++));
for (const view of views) view.setVisible(false);
advance(1000);
assert.equal(mounts, 0, 'offscreen formulas must not create Web views');
views.slice(0, 8).forEach(view => view.setVisible(true));
advance(179); assert.equal(mounts, 0, 'do not start rendering immediately during scrolling');
advance(1); assert.equal(mounts, 1, 'only one renderer may start at a time');
views[0].ready(); assert.equal(mounts, 2, 'the next renderer starts when the previous one loads');
views[1].setVisible(false); views[1].setVisible(true);
advance(1000); assert.equal(unmounts, 0, 'short scrolls reuse the existing renderer');
views[1].ready(); assert.equal(mounts, 3);
views[2].setVisible(false); views[2].dispose(); assert.equal(mounts, 4, 'disposing a loading renderer unblocks the queue');
views[3].setVisible(false); advance(3000); assert.equal(unmounts, 1, 'offscreen renderer eventually releases resources');
views.forEach(view => view.dispose()); advance(10000); assert.equal(timers.size, 0, 'disposed components leave no timers');
console.log('PASS delayed, serialized Web startup; reuse, release, disposal and 500 offscreen formulas');

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

function mount() {
  const elements = new Map();
  const head = { lastElementChild: null, appendChild(el) { this.lastElementChild = el; elements.set(el.id, el); } };
  const handlers = {};
  const document = {
    head,
    getElementById(id) { return elements.get(id) || null; },
    createElement() { return { id: '', textContent: '' }; },
    addEventListener(name, handler) { handlers[name] = handler; }
  };
  let zoom = 0;
  const window = { __lexiHandshake: { zoom(direction) { zoom += direction; } } };
  class MutationObserver { constructor(callback) { this.callback = callback; } observe() {} }
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../../entry/src/main/resources/rawfile/lexinote_appearance.js'), 'utf8'),
    { document, window, MutationObserver });
  return { document, window, handlers, getZoom: () => zoom };
}

test('appearance applies validated color, size and the enabled CSS payload', () => {
  const page = mount();
  page.window.lexiApplyAppearance('#123456', 22, false, '.example { color: red; }');
  const css = page.document.getElementById('lexi-user-appearance').textContent;
  assert.match(css, /--interactive-accent:#123456/);
  assert.match(css, /\.markdown-rendered \{font-size:22px/);
  assert.match(css, /\.example \{ color: red; \}/);
  page.window.lexiApplyAppearance('invalid', 100, false, '');
  const updated = page.document.getElementById('lexi-user-appearance').textContent;
  assert.match(updated, /--interactive-accent:#6E44D9/);
  assert.match(updated, /font-size:32px/);
  assert.doesNotMatch(updated, /\.example/);
});

test('quick zoom requires the option, Ctrl and the note body', () => {
  const page = mount();
  let prevented = 0;
  const wheel = (ctrlKey, inNote, deltaY) => page.handlers.wheel({ ctrlKey, deltaY,
    target: { closest: () => inNote }, preventDefault: () => { prevented++; } });
  wheel(true, true, -1);
  page.window.lexiApplyAppearance('#123456', 16, true, '');
  wheel(false, true, -1);
  wheel(true, false, -1);
  wheel(true, true, -1);
  wheel(true, true, 1);
  assert.equal(page.getZoom(), 0);
  assert.equal(prevented, 2);
});

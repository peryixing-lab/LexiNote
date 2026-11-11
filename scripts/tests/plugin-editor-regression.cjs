// P07/P13 · editor bridge and metadata adapter regression.
const assert = require('node:assert/strict');
const { createSandbox } = require('./lib/plugin-sandbox.cjs');

const box = createSandbox();
box.reset();
const { NoteItem } = box.load('core/LexiModels');
const { LexiEditorBridge, PluginEditorHandle } = box.load('plugin/adapters/LexiEditorBridge');
const { PluginSelectionRange } = box.load('plugin/model/PluginModels');
const { LexiMetadataAdapter } = box.load('plugin/adapters/LexiMetadataAdapter');

let assertions = 0;
const ok = (v, m) => { assertions++; assert.ok(v, m); };
const eq = (a, b, m) => { assertions++; assert.deepEqual(a, b, m); };

function handle(id, noteId, content, options = {}) {
  const state = { content, dirty: options.dirty || false, visible: options.visible !== false,
    focused: options.focused || false, readOnly: options.readOnly || false, revision: options.revision || 1 };
  const item = new PluginEditorHandle();
  item.editorId = id; item.noteId = noteId; item.vaultId = options.vaultId || 'v1'; item.windowId = 'main';
  item.isDirty = () => state.dirty;
  item.isVisible = () => state.visible;
  item.isFocused = () => state.focused;
  item.isReadOnly = () => state.readOnly;
  item.getContent = () => state.content;
  item.getBaseContent = () => state.content;
  item.getRevision = () => state.revision;
  item.getSelection = () => { const r = new PluginSelectionRange(); r.from = 0; r.to = 0; return r; };
  item.replaceRange = (start, end, text) => {
    if (state.readOnly) return false;
    state.content = state.content.substring(0, start) + text + state.content.substring(end);
    state.dirty = true; state.revision++;
    return true;
  };
  return { item, state };
}

// 1. A single focused editor becomes active.
LexiEditorBridge.reset();
const a = handle('a', 'n1', 'A 的正文');
const b = handle('b', 'n2', 'B 的正文');
LexiEditorBridge.register(a.item);
LexiEditorBridge.register(b.item);
eq(LexiEditorBridge.active(), undefined, 'two visible editors with no focus is ambiguous');
a.state.focused = true;
eq(LexiEditorBridge.active().editorId, 'a', 'the focused editor wins');
a.state.focused = false;
LexiEditorBridge.setActive('b');
eq(LexiEditorBridge.active().editorId, 'b', 'explicit activation wins');
LexiEditorBridge.unregister('b');
eq(LexiEditorBridge.active().editorId, 'a', 'unregistering the active editor falls back correctly');
console.log('PASS active editor resolution prefers focus, then explicit activation, never load order');

// 2. Read-only editors are never active.
a.state.readOnly = true;
eq(LexiEditorBridge.active(), undefined, 'a read-only editor cannot be the write target');
a.state.readOnly = false;
console.log('PASS read-only editors are skipped');

// 3. Draft detection is per note and ignores hidden editors.
a.state.dirty = true;
ok(LexiEditorBridge.hasUnsavedDraft('n1'), 'dirty note reports a draft');
ok(!LexiEditorBridge.hasUnsavedDraft('n2'), 'other note has no draft');
a.state.visible = false;
ok(!LexiEditorBridge.hasUnsavedDraft('n1'), 'an invisible editor does not block writes');
a.state.visible = true;
eq(LexiEditorBridge.dirtyNoteIds(), ['n1'], 'dirty note ids');
console.log('PASS unsaved drafts are tracked per note and per visibility');

// 4. Range replacement offsets are UTF-16 code unit offsets, like the native editor.
const c = handle('c', 'n3', '甲乙丙🦋结尾', { focused: true });
LexiEditorBridge.reset();
LexiEditorBridge.register(c.item);
const content = '甲乙丙🦋结尾';
LexiEditorBridge.replaceRange(0, 1, '【');
eq(c.state.content, '【乙丙🦋结尾', 'replace a CJK character');
LexiEditorBridge.replaceRange(c.state.content.length - 2, c.state.content.length, '】');
eq(c.state.content.endsWith('】'), true, 'replace the tail');
const emojiAt = c.state.content.indexOf('🦋');
LexiEditorBridge.replaceRange(emojiAt, emojiAt + 2, '🦋🦋');
eq(c.state.content.includes('🦋🦋'), true, 'an emoji occupies two UTF-16 units');
console.log('PASS replacements use UTF-16 offsets and keep astral characters intact');

// 5. Out-of-range indices are clamped, not thrown.
const d = handle('d', 'n4', 'abcdef', { focused: true });
LexiEditorBridge.reset();
LexiEditorBridge.register(d.item);
LexiEditorBridge.replaceRange(-5, 999, 'X');
eq(d.state.content, 'X', 'indices are clamped into the document');
console.log('PASS out-of-range edits clamp instead of corrupting the document');

// 6. No editor means an explicit error, not a silent no-op.
LexiEditorBridge.reset();
assertions++;
assert.throws(() => LexiEditorBridge.replaceRange(0, 0, 'x'), (error) => String(error.message).startsWith('E_EDITOR_READONLY'));
console.log('PASS writing without an editor fails with E_EDITOR_READONLY');

// 7. Metadata subset from the existing parser.
const note = new NoteItem();
note.id = 'meta-1';
note.content = [
  '---',
  'tags: ["课程", "复习"]',
  '状态: 进行中',
  '---',
  '# 一级标题',
  '',
  '正文提到 [[另一篇]] 和 [[目标#小节|显示名]]。',
  '嵌入：![[图片.png]]',
  '行内标签 #重要 与 #算法/图论',
  '## 二级标题',
  ''
].join('\n');
const meta = LexiMetadataAdapter.build(note, '课程/元数据.md', 3);
eq(meta.fileId, 'meta-1', 'fileId');
eq(meta.path, '课程/元数据.md', 'logical path');
eq(meta.version, 3, 'revision');
eq(meta.headings.map((h) => h.heading), ['一级标题', '二级标题'], 'headings in order');
eq(meta.headings[0].level, 1, 'heading level');
eq(meta.headings[1].line, 9, 'heading line index is absolute in the original document');
eq(meta.links.map((l) => l.link), ['另一篇', '目标'], 'wikilink targets');
eq(meta.links[1].displayText, '显示名', 'display text kept');
eq(meta.embeds, ['图片.png'], 'embed detected');
ok(meta.tags.includes('课程') && meta.tags.includes('复习'), 'frontmatter tags');
ok(meta.tags.includes('重要') && meta.tags.includes('算法/图论'), 'inline tags');
eq(meta.properties.get('状态'), '进行中', 'scalar property');
ok(meta.frontmatter.includes('状态: 进行中'), 'raw frontmatter kept');
ok(meta.supportedFields.includes('headings'), 'supported fields listed');
ok(meta.unsupportedFields.includes('sections'), 'unsupported fields listed explicitly');
ok(!meta.unsupportedFields.includes('headings'), 'a supported field is not listed as unsupported');
console.log('PASS metadata exposes only the verified subset and names the unsupported fields');

// 8. Hash is stable and content sensitive.
eq(LexiMetadataAdapter.contentHash('abc'), LexiMetadataAdapter.contentHash('abc'), 'hash is deterministic');
ok(LexiMetadataAdapter.contentHash('abc') !== LexiMetadataAdapter.contentHash('abd'), 'hash changes with content');
ok(LexiMetadataAdapter.contentHash('中文') !== LexiMetadataAdapter.contentHash('中'), 'hash covers CJK');
console.log('PASS content hash is deterministic and content sensitive');

// 9. Heading offset lookup.
const offset = LexiMetadataAdapter.headingOffset(note.content, '二级标题', 2);
eq(note.content.substring(offset, offset + 2), '##', 'heading offset points at the heading line');
eq(LexiMetadataAdapter.headingOffset(note.content, '不存在', 0), -1, 'missing heading returns -1');
console.log('PASS heading offsets resolve to the original document position');

// 10. A note without frontmatter still works.
const plain = new NoteItem();
plain.id = 'meta-2';
plain.content = '没有 YAML 的正文\n\n## 小节\n';
const plainMeta = LexiMetadataAdapter.build(plain, '纯文本.md', 1);
eq(plainMeta.frontmatter, '', 'no frontmatter');
eq(plainMeta.headings.length, 1, 'heading still parsed');
eq(plainMeta.tags, [], 'no tags');
console.log('PASS notes without frontmatter parse without inventing fields');

console.log(`\nplugin-editor-regression: ${assertions} assertions passed`);

(async () => {
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const q = (selector) => document.querySelector(selector);
  const qa = (selector) => Array.from(document.querySelectorAll(selector));
  const token = `FLUSH_${Date.now()}`;
  const block = qa('.md-block.md-editable')[0];
  block?.dispatchEvent(new MouseEvent('click', { bubbles: true }));
  await sleep(250);
  const editor = q('.live-block-editor');
  if (!editor) return { ok: false, reason: 'editor did not open', token };
  const setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value').set;
  setter.call(editor, `${editor.value} ${token}`);
  editor.dispatchEvent(new Event('input', { bubbles: true }));
  await sleep(120);
  // Close immediately after typing; the main process must ask the renderer to flush.
  void window.lexi?.window.close();
  return { ok: true, token };
})();

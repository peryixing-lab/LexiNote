(async () => {
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  await sleep(800);
  const q = (selector) => document.querySelector(selector);
  const qa = (selector) => Array.from(document.querySelectorAll(selector));
  return {
    vaultName: q('.vault-name')?.textContent ?? '',
    noteRows: qa('.note-row').length,
    spaceRows: qa('.space-row').length,
    tabs: qa('.tab').length,
    folders: qa('.folder-row').length,
    emptyHint: document.body.innerText.includes('写下第一条笔记'),
    editorEmpty: !!q('.editor-empty'),
    workspaceCount: qa('.menu-item').length
  };
})();

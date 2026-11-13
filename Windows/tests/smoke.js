(async () => {
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const results = {};
  const q = (selector) => document.querySelector(selector);
  const qa = (selector) => Array.from(document.querySelectorAll(selector));
  const click = (element) => element && element.dispatchEvent(new MouseEvent('click', { bubbles: true }));
  const setValue = (element, value) => {
    const proto = element.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    const setter = Object.getOwnPropertyDescriptor(proto, 'value').set;
    setter.call(element, value);
    element.dispatchEvent(new Event('input', { bubbles: true }));
  };
  const key = (keyName, init = {}) =>
    window.dispatchEvent(new KeyboardEvent('keydown', { key: keyName, bubbles: true, ...init }));

  try {
    results.windowTitle = document.title;
    results.initialTabs = qa('.tab').length;
    results.initialTitle = q('.document-title')?.value ?? '';
    results.initialBlockCount = qa('.md-block').length;
    results.katexRendered = qa('.katex').length > 0;

    const treeRow = qa('.note-row').find((row) => row.textContent.includes('二叉树'));
    click(treeRow);
    await sleep(450);
    results.afterSwitchTitle = q('.document-title')?.value ?? '';

    const editable = qa('.md-block.md-editable')[0];
    click(editable);
    await sleep(250);
    results.blockEditorOpened = !!q('.live-block-editor');
    const editor = q('.live-block-editor');
    if (editor) {
      setValue(editor, editor.value + ' 冒烟测试补充');
      await sleep(350);
      results.blockTyped = editor.value.includes('冒烟测试补充');
      editor.blur();
      await sleep(900);
    }
    results.status = q('.save-status')?.textContent?.trim() ?? '';
    results.bodyRenderedTestText = document.body.textContent.includes('冒烟测试补充');

    const tabsBefore = qa('.tab').length;
    key('n', { ctrlKey: true });
    await sleep(450);
    results.tabsAfterNew = qa('.tab').length;
    results.tabsBefore = tabsBefore;
    results.newNoteEditor = !!q('.document-title');

    const search = q('.sidebar-search input');
    if (search) {
      setValue(search, '二叉树');
      await sleep(350);
      results.searchRows = qa('.note-row').length;
      setValue(search, '');
      await sleep(250);
    }

    key('p', { ctrlKey: true });
    await sleep(350);
    results.paletteOpen = !!q('.palette');
    results.paletteRows = qa('.palette-row').length;
    const paletteInput = q('.palette-search input');
    if (paletteInput) {
      setValue(paletteInput, '设置');
      await sleep(250);
      results.paletteFiltered = qa('.palette-row').length;
    }
    key('Escape');
    await sleep(200);
    results.paletteClosed = !q('.palette');

    const panelButton = q('.panel-btn');
    click(panelButton);
    await sleep(350);
    results.rightSidebarOpen = !!q('.right-sidebar');
    results.outlineRows = qa('.outline-row').length;
    const outline = q('.outline-row');
    if (outline) {
      click(outline);
      await sleep(250);
      results.outlineClicked = true;
    }

    click(q('.panel-btn'));
    await sleep(200);

    const graphButton = qa('.ribbon-btn').find((button) => button.title.includes('笔记关联')) || qa('.ribbon-btn')[2];
    click(graphButton);
    await sleep(450);
    results.graphNodes = qa('.graph-node').length;
    click(qa('.ribbon-btn')[0]);
    await sleep(300);

    const library = qa('.ribbon-btn')[0];
    click(library);
    await sleep(350);
    results.sectionsReturned = qa('.note-row').length > 0;

    // --- workspace open prompt -------------------------------------------------
    click(q('.vault-switcher'));
    await sleep(320);
    let vaultItem = qa('.menu-item').find((item) => item.textContent.includes('开发项目库'));
    results.vaultMenuItem = !!vaultItem;
    click(vaultItem);
    await sleep(420);
    results.promptVisible = !!q('.workspace-open-dialog');
    results.promptVault = q('.workspace-open-dialog h2')?.textContent ?? '';
    click(q('.workspace-open-current'));
    await sleep(900);
    results.vaultAfterCurrent = q('.vault-name')?.textContent ?? '';
    results.promptClosed = !q('.workspace-open-dialog');

    click(q('.vault-switcher'));
    await sleep(320);
    vaultItem = qa('.menu-item').find((item) => item.textContent.includes('个人知识库'));
    click(vaultItem);
    await sleep(420);
    results.promptAgain = !!q('.workspace-open-dialog');
    const suppressBox = q('.workspace-open-suppress input');
    if (suppressBox) {
      suppressBox.click();
      await sleep(120);
    }
    click(q('.workspace-open-new'));
    await sleep(1800);
    results.windowCount = await (window.lexi?.window.count() ?? Promise.resolve(0));
    results.windowVaults = await (window.lexi?.window.vaults() ?? Promise.resolve([]));
    results.promptClosedAfterNew = !q('.workspace-open-dialog');

    // --- per-workspace open mode + re-enable prompt ---------------------------
    click(qa('.ribbon-btn').at(-1));
    await sleep(420);
    const editorCategory = qa('.settings-category').find((item) => item.textContent.includes('编辑器'));
    click(editorCategory);
    await sleep(320);
    const promptSwitch = q('.settings-window button[role="switch"][aria-label="选择工作区时不再提示"]');
    results.promptSwitchFound = !!promptSwitch;
    if (promptSwitch && promptSwitch.getAttribute('aria-checked') === 'true') {
      click(promptSwitch);
      await sleep(220);
    }
    const devRow = qa('.workspace-mode-row').find((row) => row.textContent.includes('开发项目库'));
    const devSelect = devRow?.querySelector('select');
    results.devModeSelectFound = !!devSelect;
    if (devSelect) {
      const setter = Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, 'value')?.set;
      setter?.call(devSelect, 'new');
      devSelect.dispatchEvent(new Event('change', { bubbles: true }));
      await sleep(420);
    }
    click(q('.settings-content-head .icon-btn'));
    await sleep(320);
    results.settingsClosed = !q('.settings-window');

    click(q('.vault-switcher'));
    await sleep(320);
    click(qa('.menu-item').find((item) => item.textContent.includes('个人知识库')));
    await sleep(380);
    results.promptReenabled = !!q('.workspace-open-dialog');
    click(q('.workspace-open-current'));
    await sleep(760);
    results.vaultAfterReenable = q('.vault-name')?.textContent ?? '';

    click(q('.vault-switcher'));
    await sleep(320);
    click(qa('.menu-item').find((item) => item.textContent.includes('开发项目库')));
    await sleep(1800);
    results.perWorkspaceNoPrompt = !q('.workspace-open-dialog');
    results.windowCountAfterMode = await (window.lexi?.window.count() ?? Promise.resolve(0));
    results.windowVaultsAfterMode = await (window.lexi?.window.vaults() ?? Promise.resolve([]));

    // --- cross-window save sync ----------------------------------------------
    await window.lexi?.openWorkspaceWindow('default-vault');
    await sleep(1700);
    key('n', { ctrlKey: true });
    await sleep(1700);
    results.syncProbe = await (window.lexi?.window.probe() ?? Promise.resolve([]));
    results.syncWindowCount = await (window.lexi?.window.count() ?? Promise.resolve(0));

    try {
      localStorage.setItem('lexi-smoke', '1');
      results.localStorage = localStorage.getItem('lexi-smoke') === '1';
    } catch (error) {
      results.localStorage = false;
    }

    results.done = true;
  } catch (error) {
    results.error = String((error && error.stack) || error);
  }
  return results;
})();

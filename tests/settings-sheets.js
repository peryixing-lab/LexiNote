(async () => {
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const q = (selector) => document.querySelector(selector);
  const qa = (selector) => Array.from(document.querySelectorAll(selector));
  const click = (element) => element?.click();
  const key = (name, target = window, options = {}) => target.dispatchEvent(
    new KeyboardEvent('keydown', { key: name, bubbles: true, cancelable: true, ...options })
  );
  const failures = [];
  const checks = {};
  const assert = (condition, name, detail) => {
    checks[name] = Boolean(condition);
    if (!condition) failures.push(`${name}: ${JSON.stringify(detail)}`);
  };
  const waitFor = async (predicate) => {
    for (let i = 0; i < 100; i++) {
      if (predicate()) return;
      await sleep(16);
    }
    throw new Error('Timed out waiting for sheet state');
  };
  const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const y = (panel) => {
    const transform = getComputedStyle(panel).transform;
    return transform === 'none' ? 0 : new DOMMatrixReadOnly(transform).m42;
  };
  try {
    window.__lexiShot('workspace');
    await sleep(350);
    const opener = qa('.ribbon-btn').at(-1);
    opener.focus();
    click(opener);
    await waitFor(() => q('.settings-window'));
    const panel = q('.settings-window');
    const startY = y(panel);
    await sleep(90);
    const midY = y(panel);
    await sleep(360);
    assert(reducedMotion ? startY === 0 && midY === 0 : startY > midY && midY > 0,
      'settings slides upward', { startY, midY });
    assert(Math.abs(y(panel)) < 1, 'settings settles at center', y(panel));
    assert(qa('.settings-category').map((item) => item.textContent).join('|') ===
      '关于|外观|界面|编辑器|文件与链接|插件|快捷键', 'category order matches desktop ports');
    assert(panel.textContent.includes('版本') && panel.textContent.includes('语言') &&
      panel.textContent.includes('更改工作区文件夹'), 'about groups version language and storage');
    assert(panel.contains(document.activeElement), 'focus enters settings');
    const controls = Array.from(panel.querySelectorAll('button, input, select')).filter((item) => !item.disabled);
    controls.at(-1).focus();
    key('Tab', document.activeElement);
    assert(document.activeElement === controls[0], 'tab wraps inside settings');
    key('Tab', document.activeElement, { shiftKey: true });
    assert(document.activeElement === controls.at(-1), 'shift tab wraps inside settings');

    click(qa('.settings-category').find((item) => item.textContent === '界面'));
    await sleep(80);
    assert(q('.settings-page-title')?.textContent === '界面' &&
      q('.settings-content').textContent.includes('缩放比例'), 'interface has its own controls');
    const toggle = q('[aria-label="显示标签页标题栏"]');
    const before = toggle.getAttribute('aria-checked');
    click(toggle);
    await sleep(50);
    assert(q('[aria-label="显示标签页标题栏"]').getAttribute('aria-checked') !== before,
      'interface toggle updates state');
    click(q('[aria-label="显示标签页标题栏"]'));

    click(qa('.settings-category').find((item) => item.textContent === '文件与链接'));
    await sleep(60);
    assert(q('.settings-content').textContent.includes('Wiki 双向链接') &&
      q('.settings-content').textContent.includes('工作区归档 (.zip)') &&
      q('.settings-content').textContent.includes('版本历史与自动清理'), 'file page preserves backups and history');
    const scroll = q('.settings-scroll');
    scroll.scrollTop = 250;
    click(qa('.settings-category').find((item) => item.textContent === '编辑器'));
    await sleep(60);
    assert(q('.settings-scroll').scrollTop === 0 && q('.workspace-mode-row select'),
      'category changes reset scroll and retain workspace preferences');

    key('Escape', panel);
    await sleep(50);
    assert(!!q('.settings-window'), 'settings remains mounted during exit');
    assert(reducedMotion || y(panel) > 0, 'settings exits downward', y(panel));
    await waitFor(() => !q('.settings-window'));
    assert(document.activeElement === opener, 'focus returns to opener');

    // Reopening during dismissal must cancel the pending unmount.
    click(opener);
    await sleep(130);
    key('Escape', q('.settings-window'));
    await sleep(40);
    key(',', window, { ctrlKey: true });
    await sleep(450);
    assert(!!q('.settings-window') && Math.abs(y(q('.settings-window'))) < 1,
      'rapid close and reopen keeps settings visible');
    q('.workspace-sheet').dispatchEvent(new PointerEvent('pointerdown', { bubbles: true }));
    await waitFor(() => !q('.settings-window'));
    assert(!q('.workspace-sheet'), 'backdrop dismisses settings');

    window.__lexiShot('trash');
    await waitFor(() => q('.trash-dialog'));
    const trash = q('.trash-dialog');
    const trashY = y(trash);
    await sleep(90);
    const trashMidY = y(trash);
    await sleep(360);
    assert(reducedMotion ? trashY === 0 && trashMidY === 0 : trashY > trashMidY && trashMidY > 0,
      'trash slides upward', { trashY, trashMidY });
    assert(trash.getBoundingClientRect().height === 560, 'trash has consistent sheet height');
    key('Escape', trash);
    await sleep(50);
    assert(!!q('.trash-dialog') && (reducedMotion || y(trash) > 0), 'trash exits downward');
    await waitFor(() => !q('.trash-dialog'));
    assert(!q('.workspace-sheet'), 'trash fully dismisses');

    // Exercise the screenshot/deep-link entry points after another category is open.
    window.__lexiShot('interface');
    await sleep(400);
    window.__lexiShot('data');
    await sleep(400);
    assert(q('.settings-page-title')?.textContent === '文件与链接', 'data entry point opens file page');
    window.__lexiShot('trash');
    await waitFor(() => q('.trash-dialog') && !q('.settings-window'));
    assert(!!q('.trash-dialog') && !q('.settings-window'), 'trash entry point replaces settings');
  } catch (error) {
    failures.push(String(error.stack || error));
  }
  return { passed: failures.length === 0, reducedMotion, checks, failures };
})();

(async () => {
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const q = (selector) => document.querySelector(selector);
  const qa = (selector) => Array.from(document.querySelectorAll(selector));
  const click = (element) => {
    if (!element) throw new Error('Expected clickable element but got null');
    element.dispatchEvent(new MouseEvent('click', { bubbles: true }));
  };
  const setValue = (element, value) => {
    const proto = element.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    const setter = Object.getOwnPropertyDescriptor(proto, 'value').set;
    setter.call(element, value);
    element.dispatchEvent(new Event('input', { bubbles: true }));
  };
  const key = (keyName, init = {}) =>
    window.dispatchEvent(new KeyboardEvent('keydown', { key: keyName, bubbles: true, ...init }));

  async function waitFor(predicate, label, timeoutMs = 9000) {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
      try {
        const value = await predicate();
        if (value) return value;
      } catch {
        // Retry until timeout.
      }
      await sleep(120);
    }
    throw new Error(`Timed out waiting for: ${label}`);
  }

  async function runPaletteCommand(titleNeedle) {
    key('p', { ctrlKey: true });
    await waitFor(() => q('.palette-search input'), `palette open for ${titleNeedle}`);
    const input = q('.palette-search input');
    setValue(input, titleNeedle);
    const row = await waitFor(
      () => qa('.palette-row').find((el) => el.textContent && el.textContent.includes(titleNeedle)),
      `palette row "${titleNeedle}"`
    );
    click(row);
    await waitFor(() => !q('.palette'), `palette closed after ${titleNeedle}`);
  }

  const failures = [];
  function assert(condition, name, detail) {
    if (!condition) {
      const msg = detail === undefined ? name : `${name} (${JSON.stringify(detail)})`;
      failures.push(msg);
      console.error('ASSERTION_FAILED:', msg);
    }
    return Boolean(condition);
  }

  const results = { checks: {}, failures };

  try {
    const runtimeInfo = await window.lexi.runtimeInfo();
    const stateEnv = await window.lexi.loadState();
    const vaultId = stateEnv.state?.settings?.lastVaultId || stateEnv.state?.vaults?.[0]?.id || 'default-vault';
    const rootDir = runtimeInfo.userDataPath.replace(/[\\/]user-data$/, '');
    const fixturesDir = `${rootDir}/fixtures`;
    const harnessZip = `${fixturesDir}/harness-lexinote-harness.zip`;

    // ------------------------------------------------------------------ 1. Security: Bad ZIP rejections
    const slipInstall = await window.lexi.plugins.installZipPath(`${fixturesDir}/malicious-slip.zip`);
    assert(!slipInstall.ok && slipInstall.error.includes('E_INSTALL_REJECTED'), 'reject_zip_slip', slipInstall);
    results.checks.rejectZipSlip = !slipInstall.ok;

    const symlinkInstall = await window.lexi.plugins.installZipPath(`${fixturesDir}/malicious-symlink.zip`);
    assert(!symlinkInstall.ok && symlinkInstall.error.includes('E_INSTALL_REJECTED'), 'reject_symlink_zip', symlinkInstall);
    results.checks.rejectSymlinkZip = !symlinkInstall.ok;

    // ------------------------------------------------------------------ 2. Native LexiNote Plugin (.zip + commonRoot)
    const nativeInstall = await window.lexi.plugins.installZipPath(`${fixturesDir}/native-plugin.zip`);
    assert(nativeInstall.ok && nativeInstall.record?.id === 'test.native.suite', 'install_native_zip', nativeInstall);
    assert(nativeInstall.record?.kind === 'lexinote', 'native_kind', nativeInstall.record?.kind);
    results.checks.nativeInstalled = nativeInstall.ok;

    // Grant ONLY plugin.storage & ui.commands initially so boot probe tests ungranted vault.read -> E_PERMISSION_DENIED
    await window.lexi.plugins.grantCapability('test.native.suite', 'plugin.storage');
    await window.lexi.plugins.grantCapability('test.native.suite', 'ui.commands');
    await window.lexi.plugins.setEnabled(vaultId, 'test.native.suite', true);

    const probesRaw = await waitFor(
      async () => {
        const raw = await window.lexi.plugins.storageGet('test.native.suite', vaultId, 'boot_probes');
        return raw && raw.includes('ungrantedVaultReadError') ? raw : '';
      },
      'native boot_probes written'
    );
    const bootProbes = JSON.parse(probesRaw);
    assert(!bootProbes.hasPreloadBridge, 'iframe_has_no_preload_bridge', bootProbes);
    assert(
      String(bootProbes.unsupportedModuleBlocked).includes('E_UNSUPPORTED_MODULE'),
      'iframe_blocks_require_fs',
      bootProbes
    );
    assert(
      String(bootProbes.ungrantedVaultReadError).includes('E_PERMISSION_DENIED'),
      'ungranted_rpc_returns_permission_denied',
      bootProbes
    );
    results.checks.sandboxIsolation = {
      noPreload: !bootProbes.hasPreloadBridge,
      noFsModule: String(bootProbes.unsupportedModuleBlocked).includes('E_UNSUPPORTED_MODULE'),
      ungrantedDenied: String(bootProbes.ungrantedVaultReadError).includes('E_PERMISSION_DENIED')
    };

    // Assert sandbox iframe DOM isolation from parent
    const nativeIframe = await waitFor(
      () => q('iframe[title="plugin-runtime-test.native.suite"]'),
      'native plugin iframe mounted'
    );
    assert(nativeIframe.getAttribute('sandbox') === 'allow-scripts', 'iframe_sandbox_attr', nativeIframe.getAttribute('sandbox'));
    assert(nativeIframe.contentDocument === null, 'iframe_opaque_origin_parent_blocked', nativeIframe.contentDocument);

    // Open Settings -> Plugins via UI & grant all permissions through UI confirm dialog
    click(qa('.ribbon-btn').find((el) => el.title && el.title.includes('设置')));
    await waitFor(() => q('.settings-categories'), 'settings dialog open');
    const pluginsNav = qa('.settings-category').find((btn) => btn.textContent && btn.textContent.includes('插件'));
    click(pluginsNav);
    await waitFor(() => q('.plugin-manager'), 'plugin manager open');

    const nativeCard = await waitFor(
      () => qa('.plugin-card').find((card) => card.textContent && card.textContent.includes('test.native.suite')),
      'native plugin card in settings'
    );
    const grantAllBtn = Array.from(nativeCard.querySelectorAll('button')).find((b) =>
      b.textContent && b.textContent.includes('授予全部权限')
    );
    click(grantAllBtn);
    const confirmGrantBtn = await waitFor(
      () => qa('.plugin-confirm-card button').find((b) => b.textContent && b.textContent.includes('确认授予')),
      'grant-all confirm button'
    );
    click(confirmGrantBtn);
    await waitFor(() => !q('.plugin-confirm-card'), 'grant-all confirm closed');
    await waitFor(
      () => nativeCard.textContent && nativeCard.textContent.includes('已启用'),
      'native plugin reloaded and active'
    );
    click(q('.settings-topbar-close'));
    await sleep(300);
    if (q('.settings-overlay, .settings-window')) {
      key('Escape');
      await sleep(200);
    }

    // Run Vault + Metadata + Workspace + Notice command via Command Palette
    await runPaletteCommand('Native: Run Vault Flow');
    const vaultFlowRaw = await waitFor(
      () => window.lexi.plugins.storageGet('test.native.suite', vaultId, 'vault_flow'),
      'native vault_flow storage'
    );
    const vaultFlow = JSON.parse(vaultFlowRaw);
    assert(vaultFlow.createdPath === 'native-created.md', 'native_vault_create_path', vaultFlow);
    assert(vaultFlow.headings.includes('Native Note'), 'native_metadata_headings', vaultFlow);
    assert(vaultFlow.tags.includes('native-tag'), 'native_metadata_tags', vaultFlow);
    assert(vaultFlow.links.includes('Target'), 'native_metadata_links', vaultFlow);
    assert(
      Boolean(qa('.plugin-notice-toast').find((el) => el.textContent && el.textContent.includes('Native Vault Flow OK'))),
      'native_ui_notice_rendered'
    );
    await waitFor(
      () => q('.document-title')?.value === 'native-created',
      'workspace.openFile switched editor to native-created'
    );
    results.checks.nativeVaultAndMetadata = vaultFlow;

    // Run Editor Selection Replacement via Command Palette
    await runPaletteCommand('Native: Insert Into Editor');
    const editorFlowRaw = await waitFor(
      () => window.lexi.plugins.storageGet('test.native.suite', vaultId, 'editor_flow'),
      'native editor_flow storage'
    );
    const editorFlow = JSON.parse(editorFlowRaw);
    assert(editorFlow.hadActive === true, 'editor_active_present', editorFlow);
    assert(editorFlow.afterContent.includes('[INSERTED]'), 'editor_replace_selection_applied', editorFlow);
    await waitFor(
      () => document.body.textContent && document.body.textContent.includes('[INSERTED]'),
      'editor DOM shows [INSERTED]'
    );

    // Verify events.on('vault.modified') delivered after editor edit
    const afterEventRaw = await waitFor(
      async () => {
        const raw = await window.lexi.plugins.storageGet('test.native.suite', vaultId, 'boot_probes');
        const parsed = raw ? JSON.parse(raw) : null;
        return parsed && Array.isArray(parsed.vaultModifiedEvents) && parsed.vaultModifiedEvents.length > 0
          ? raw
          : '';
      },
      'vault.modified event delivered to native plugin'
    );
    results.checks.vaultModifiedEventsCount = JSON.parse(afterEventRaw).vaultModifiedEvents.length;

    // Verify storage persistence across disable + re-enable
    await runPaletteCommand('Native: Write Persistent Key');
    await waitFor(
      async () => {
        const raw = await window.lexi.plugins.storageGet('test.native.suite', vaultId, 'persist_count');
        return raw && JSON.parse(raw).count === 1;
      },
      'persist_count === 1'
    );
    await window.lexi.plugins.setEnabled(vaultId, 'test.native.suite', false);
    await sleep(300);
    await window.lexi.plugins.setEnabled(vaultId, 'test.native.suite', true);
    await waitFor(
      () => q('iframe[title="plugin-runtime-test.native.suite"]'),
      'native iframe rebooted'
    );
    await runPaletteCommand('Native: Write Persistent Key');
    const persistAfter = await waitFor(
      async () => {
        const raw = await window.lexi.plugins.storageGet('test.native.suite', vaultId, 'persist_count');
        return raw && JSON.parse(raw).count === 2 ? JSON.parse(raw) : null;
      },
      'persist_count === 2 across reload'
    );
    results.checks.storagePersistence = persistAfter;

    // Verify live capability revocation blocks immediately & path traversal returns E_INVALID_PATH
    await window.lexi.plugins.revokeCapability('test.native.suite', 'vault.write');
    await runPaletteCommand('Native: Probe Revoked Write');
    const revokedWriteRaw = await waitFor(
      () => window.lexi.plugins.storageGet('test.native.suite', vaultId, 'revoked_write_probe'),
      'revoked_write_probe stored'
    );
    const revokedWrite = JSON.parse(revokedWriteRaw);
    assert(String(revokedWrite.errorText).includes('E_PERMISSION_DENIED'), 'revoke_blocks_immediately', revokedWrite);

    await window.lexi.plugins.grantCapability('test.native.suite', 'vault.write');
    await runPaletteCommand('Native: Probe Path Traversal');
    const traversalRaw = await waitFor(
      () => window.lexi.plugins.storageGet('test.native.suite', vaultId, 'traversal_probe'),
      'traversal_probe stored'
    );
    const traversal = JSON.parse(traversalRaw);
    assert(String(traversal.errorText).includes('E_INVALID_PATH'), 'path_traversal_rejected', traversal);

    // Open Native plugin view tab in RightSidebar and verify iframe docks cleanly
    if (!q('.right-sidebar')) {
      click(q('.panel-btn'));
      await waitFor(() => q('.right-sidebar'), 'right sidebar open');
    }
    const nativeTab = await waitFor(
      () => qa('.right-toolbar button').find((btn) => btn.title === 'Native Test Suite'),
      'Native plugin right-sidebar tab'
    );
    click(nativeTab);
    await waitFor(
      () => {
        const frame = q('iframe[title="plugin-runtime-test.native.suite"]');
        if (!frame) return null;
        const r = frame.getBoundingClientRect();
        return r.width > 180 && r.height > 180 && r.left >= 0 ? r : null;
      },
      'native iframe docked inside right sidebar'
    );
    results.checks.nativeDockedRect = q('iframe[title="plugin-runtime-test.native.suite"]').getBoundingClientRect().toJSON();

    // ------------------------------------------------------------------ 3. Upstream Harness ZIP
    const harnessInstall = await window.lexi.plugins.installZipPath(harnessZip);
    assert(harnessInstall.ok && harnessInstall.record?.id === 'lexinote.harness', 'install_harness_zip', harnessInstall);
    const harnessStarTab = await waitFor(
      () => qa('.right-toolbar button').find((btn) => btn.title && btn.title.includes('Harness')),
      'Harness star tab visible in RightSidebar'
    );
    click(harnessStarTab);
    // Before granting permissions, Harness fails cleanly with E_PERMISSION_DENIED + buttons
    const harnessErrorBox = await waitFor(
      () => q('.plugin-pane-error'),
      'Harness permission-denied card in RightSidebar'
    );
    assert(harnessErrorBox.textContent.includes('E_PERMISSION_DENIED'), 'harness_requires_permissions', harnessErrorBox.textContent);

    await window.lexi.plugins.grantAllCapabilities('lexinote.harness');
    const retryBtn = qa('.plugin-pane-actions button').find((btn) => btn.textContent && btn.textContent.includes('重试'));
    click(retryBtn);
    await waitFor(
      () => {
        const frame = q('iframe[title="plugin-runtime-lexinote.harness"]');
        if (!frame) return false;
        const r = frame.getBoundingClientRect();
        return q('.plugin-surface-slot') && r.width > 180 && r.height > 180 && r.left >= 0;
      },
      'Harness view docked and active in RightSidebar'
    );
    // Confirm Harness command appears in Command Palette
    key('p', { ctrlKey: true });
    await waitFor(() => q('.palette-search input'), 'palette open for Harness command check');
    setValue(q('.palette-search input'), 'Harness：');
    const harnessCmd = await waitFor(
      () => qa('.palette-row').find((el) => el.textContent && el.textContent.includes('Harness：新建会话')),
      'Harness command registered in palette'
    );
    assert(Boolean(harnessCmd), 'harness_command_palette_entry');
    key('Escape');
    await waitFor(() => !q('.palette'), 'palette closed');
    results.checks.harnessInstalledAndActive = true;

    // ------------------------------------------------------------------ 4. Obsidian Compat Plugin (Folder install)
    const obsInstall = await window.lexi.plugins.installFolderPath(`${fixturesDir}/obsidian-compat-suite`);
    assert(obsInstall.ok && obsInstall.record?.id === 'test-obsidian-suite', 'install_obsidian_folder', obsInstall);
    assert(obsInstall.record?.kind === 'obsidian', 'obsidian_kind', obsInstall.record?.kind);

    await window.lexi.plugins.grantAllCapabilities('test-obsidian-suite');
    await window.lexi.plugins.setEnabled(vaultId, 'test-obsidian-suite', true);
    const obsIframe = await waitFor(
      () => q('iframe[title="plugin-runtime-test-obsidian-suite"]'),
      'Obsidian iframe mounted'
    );

    // Status bar item from addStatusBarItem()
    const obsStatusReady = await waitFor(
      () => qa('.plugin-status-item').find((el) => el.textContent && el.textContent.includes('OBS:ready')),
      'Obsidian status bar item rendered'
    );
    assert(Boolean(obsStatusReady), 'obsidian_status_bar_ready');

    // Ribbon icon from addRibbonIcon() -> opens Modal overlay & Notice
    const obsRibbon = await waitFor(
      () => qa('.rail .ribbon-btn').find((el) => el.title === 'Open Obsidian Test Modal'),
      'Obsidian ribbon button rendered'
    );
    click(obsRibbon);
    await waitFor(
      () => q('iframe.plugin-runtime-iframe.plugin-iframe-modal') === obsIframe,
      'Obsidian Modal elevated iframe to modal overlay'
    );
    assert(
      Boolean(qa('.plugin-notice-toast').find((el) => el.textContent && el.textContent.includes('Ribbon modal opened'))),
      'obsidian_modal_notice'
    );

    // Close modal state cleanly by triggering Obsidian sidebar presentation (present()) or check command execution
    const obsTab = await waitFor(
      () => qa('.right-toolbar button').find((btn) => btn.title === 'Obsidian Compat Suite'),
      'Obsidian RightSidebar tab'
    );
    await runPaletteCommand('Obsidian: Run Compat Checks');
    const obsDataRaw = await waitFor(
      async () => {
        const raw = await window.lexi.plugins.storageGet('test-obsidian-suite', vaultId, 'plugin-data');
        return raw && raw.includes('normalizedPath') ? raw : '';
      },
      'Obsidian compat report saved'
    );
    const obsData = JSON.parse(obsDataRaw);
    assert(obsData.report?.isDesktop === true && obsData.report?.isDesktopApp === true, 'obsidian_platform_desktop', obsData.report);
    assert(obsData.report?.isMobile === false, 'obsidian_platform_not_mobile', obsData.report);
    assert(obsData.report?.normalizedPath === 'a/c.md', 'obsidian_normalizePath', obsData.report);
    assert(obsData.report?.createdPath === 'obsidian-note.md', 'obsidian_vault_create_modify', obsData.report);
    assert(String(obsData.report?.adapterError).includes('E_UNSUPPORTED_API'), 'obsidian_adapter_rejected', obsData.report);
    assert(String(obsData.report?.requestUrlError).includes('E_UNSUPPORTED_API'), 'obsidian_requestUrl_rejected', obsData.report);
    await waitFor(
      () => qa('.plugin-status-item').find((el) => el.textContent && el.textContent.includes('OBS:done')),
      'Obsidian status bar text updated live'
    );
    click(obsTab);
    await sleep(300);
    results.checks.obsidianCompat = obsData.report;

    // ------------------------------------------------------------------ 5. Uninstall & Data Retention
    await window.lexi.plugins.uninstall('test.native.suite', true);
    const nativePersistAfterUninstall = await window.lexi.plugins.storageGet('test.native.suite', vaultId, 'persist_count');
    assert(nativePersistAfterUninstall.includes('"count":2'), 'uninstall_keep_data_preserves_kv', nativePersistAfterUninstall);

    await window.lexi.plugins.uninstall('test-obsidian-suite', false);
    const obsDataAfterPurge = await window.lexi.plugins.storageGet('test-obsidian-suite', vaultId, 'plugin-data');
    assert(obsDataAfterPurge === '', 'uninstall_purge_removes_kv', obsDataAfterPurge);

    await window.lexi.plugins.uninstall('lexinote.harness', false);
    const finalCatalog = await window.lexi.plugins.list();
    assert(finalCatalog.records.length === 0, 'all_plugins_uninstalled', finalCatalog.records.length);

    results.passed = failures.length === 0;
  } catch (error) {
    failures.push(error && error.stack ? error.stack : String(error));
    results.passed = false;
  }

  return results;
})();

import React, { useState } from 'react';
import { useStore } from '../store/AppStore';
import {
  HARNESS_PLUGIN_ID,
  PLUGIN_CAPABILITY_META,
  usePluginHost
} from '../plugins/PluginHostController';
import type { PluginRecord, PluginRuntimeInfo } from '../../shared/pluginTypes';
import { Icon } from './Icon';

function stateBadgeLabel(
  record: PluginRecord,
  info: PluginRuntimeInfo | undefined,
  enabled: boolean,
  tr: (source: string, args?: (string | number)[]) => string
): { label: string; tone: 'active' | 'warn' | 'error' | 'muted' } {
  const allGranted =
    record.requestedCapabilities.length === 0 ||
    record.requestedCapabilities.every((cap) => record.grantedCapabilities.includes(cap));
  if (!enabled) {
    return { label: tr('未启用'), tone: 'muted' };
  }
  if (info?.state === 'failed') {
    if (allGranted && info.lastError.includes('E_PERMISSION_DENIED')) {
      return { label: tr('待重试'), tone: 'warn' };
    }
    return { label: tr('运行异常'), tone: 'error' };
  }
  if (info?.state === 'starting') {
    return { label: tr('启动中'), tone: 'warn' };
  }
  if (info?.state === 'active') {
    return { label: tr('已启用'), tone: 'active' };
  }
  return { label: tr('未启用'), tone: 'muted' };
}

function kindBadgeLabel(
  record: PluginRecord,
  tr: (source: string, args?: (string | number)[]) => string
): string {
  return record.kind === 'obsidian' ? tr('Obsidian 兼容') : tr('LexiNote 原生');
}

export function PluginSettingsSection(): JSX.Element {
  const { actions, derived } = useStore();
  const pluginHost = usePluginHost();
  const { tr } = derived;

  const [busy, setBusy] = useState(false);
  const [statusMessage, setStatusMessage] = useState('');
  const [expandedIds, setExpandedIds] = useState<Record<string, boolean>>({});
  const [confirmGrantAllPlugin, setConfirmGrantAllPlugin] = useState<PluginRecord | null>(null);
  const [confirmUninstallPlugin, setConfirmUninstallPlugin] = useState<PluginRecord | null>(null);
  const [purgeOnUninstall, setPurgeOnUninstall] = useState(false);

  const runBusy = async (task: () => Promise<void>): Promise<void> => {
    if (busy) { return; }
    setBusy(true);
    setStatusMessage('');
    try {
      await task();
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      setStatusMessage(msg);
      actions.showToast(msg);
    } finally {
      setBusy(false);
    }
  };

  const toggleExpand = (pluginId: string): void => {
    setExpandedIds((previous) => ({ ...previous, [pluginId]: !previous[pluginId] }));
  };

  const handleInstallZip = (): void => {
    void runBusy(async () => {
      const result = await pluginHost.installZip();
      if (result.ok && result.record) {
        setStatusMessage(tr('已安装「{0}」，可在下方授权并启用。', [result.record.name]));
      } else if (!result.cancelled && result.error) {
        setStatusMessage(result.error);
      }
    });
  };

  const handleToggleEnabled = (record: PluginRecord, enabled: boolean): void => {
    void runBusy(async () => {
      if (enabled) {
        await pluginHost.disablePlugin(record.id);
        setStatusMessage(tr('已停用「{0}」。', [record.name]));
      } else {
        await pluginHost.enablePlugin(record.id);
        setStatusMessage(tr('已启用「{0}」。', [record.name]));
      }
    });
  };

  const handleGrantAllConfirm = (): void => {
    const target = confirmGrantAllPlugin;
    setConfirmGrantAllPlugin(null);
    if (!target) { return; }
    void runBusy(async () => {
      await pluginHost.grantAllCapabilities(target.id);
      if (pluginHost.enabledIds.includes(target.id)) {
        await pluginHost.retryPlugin(target.id);
        setStatusMessage(tr('已授予「{0}」全部权限并重新加载。', [target.name]));
      } else {
        setStatusMessage(tr('已授予「{0}」全部声明权限。', [target.name]));
      }
    });
  };

  const handleRevokeAll = (record: PluginRecord): void => {
    void runBusy(async () => {
      await pluginHost.revokeAllCapabilities(record.id);
      if (pluginHost.enabledIds.includes(record.id)) {
        await pluginHost.disablePlugin(record.id);
      }
      setStatusMessage(tr('已撤回「{0}」的全部权限。', [record.name]));
    });
  };

  const handleToggleCapability = (record: PluginRecord, capability: string, granted: boolean): void => {
    void runBusy(async () => {
      if (granted) {
        await pluginHost.revokeCapability(record.id, capability);
      } else {
        await pluginHost.grantCapability(record.id, capability);
      }
    });
  };

  const handleUninstallConfirm = (): void => {
    const target = confirmUninstallPlugin;
    const keepData = !purgeOnUninstall;
    setConfirmUninstallPlugin(null);
    setPurgeOnUninstall(false);
    if (!target) { return; }
    void runBusy(async () => {
      await pluginHost.uninstallPlugin(target.id, keepData);
      setStatusMessage(tr('已卸载「{0}」。', [target.name]));
    });
  };

  const openPluginSideView = (record: PluginRecord): void => {
    actions.closeSettings();
    actions.setRightSidebar(true, `plugin:${record.id}`);
    if (!pluginHost.enabledIds.includes(record.id)) {
      void pluginHost.enablePlugin(record.id);
    } else {
      void pluginHost.presentPluginView(record.id, '');
    }
  };

  return (
    <div className="plugin-manager">
      <div className="plugin-manager-head">
        <div>
          <h2 className="settings-page-title" style={{ marginBottom: 4 }}>{tr('插件管理')}</h2>
          <p className="settings-note plugin-manager-sub">
            {tr('支持安装本地插件压缩包，启用后按声明权限在独立沙箱中运行。')}
          </p>
        </div>
        <div className="plugin-install-actions">
          <button type="button" className="settings-btn-inset" disabled={busy} onClick={handleInstallZip}>
            {tr('从本地安装 ZIP…')}
          </button>
        </div>
      </div>

      {statusMessage ? <div className="plugin-status-banner">{statusMessage}</div> : null}

      {pluginHost.records.length === 0 ? (
        <div className="plugin-empty-card">
          <Icon name="shield" size={24} />
          <div>
            <strong>{tr('尚未安装任何插件')}</strong>
            <p>
              {tr('点击上方“从本地安装 ZIP…”，选择包含 manifest.json 与 main.js 的插件压缩包。')}
            </p>
          </div>
        </div>
      ) : (
        <div className="plugin-card-list">
          {pluginHost.records.map((record) => {
            const enabled = pluginHost.enabledIds.includes(record.id);
            const info = pluginHost.runtimeInfoById[record.id];
            const badge = stateBadgeLabel(record, info, enabled, tr);
            const expanded = Boolean(expandedIds[record.id]);
            const allGranted =
              record.requestedCapabilities.length > 0 &&
              record.requestedCapabilities.every((cap) => record.grantedCapabilities.includes(cap));
            const diagnostics = info?.diagnostics ?? [];
            const canOpenView =
              record.id === HARNESS_PLUGIN_ID ||
              record.kind === 'obsidian' ||
              Boolean(info?.hasViews);

            return (
              <div className="plugin-card" key={record.id}>
                <div className="plugin-card-top">
                  <div className="plugin-card-info">
                    <div className="plugin-card-title-row">
                      <strong className="plugin-card-name">{record.name || record.id}</strong>
                      <span className="plugin-badge">{`v${record.version}`}</span>
                      <span className="plugin-badge">{kindBadgeLabel(record, tr)}</span>
                      <span className={`plugin-badge tone-${badge.tone}`}>{badge.label}</span>
                      {record.isDesktopOnly ? (
                        <span className="plugin-badge">{tr('桌面优先')}</span>
                      ) : null}
                    </div>
                    <div className="plugin-card-id mono">
                      {record.id}
                      {record.author ? ` · ${record.author}` : ''}
                    </div>
                    {record.description ? (
                      <div className="plugin-card-desc">{record.description}</div>
                    ) : null}
                  </div>

                  <div className="plugin-card-controls">
                    {enabled && canOpenView ? (
                      <button
                        type="button"
                        className="small-btn"
                        disabled={busy}
                        onClick={() => openPluginSideView(record)}
                      >
                        {tr('打开视图')}
                      </button>
                    ) : null}
                    {enabled && info?.state === 'failed' ? (
                      <button
                        type="button"
                        className="small-btn"
                        disabled={busy}
                        onClick={() => void runBusy(() => pluginHost.retryPlugin(record.id))}
                      >
                        {tr('重试')}
                      </button>
                    ) : null}
                    <button
                      type="button"
                      role="switch"
                      aria-checked={enabled}
                      aria-label={tr('启用插件 {0}', [record.name || record.id])}
                      className={`toggle${enabled ? ' on' : ''}`}
                      disabled={busy}
                      onClick={() => handleToggleEnabled(record, enabled)}
                    >
                      <span className="toggle-knob" />
                    </button>
                  </div>
                </div>

                {info?.lastError ? (
                  <div className="plugin-error-box">{info.lastError}</div>
                ) : null}

                {info?.warnings && info.warnings.length > 0 ? (
                  <div className="plugin-warning-box">{info.warnings.join(' · ')}</div>
                ) : null}

                <div className="plugin-card-bar">
                  <div className="plugin-card-bar-left">
                    <button
                      type="button"
                      className="small-btn"
                      onClick={() => toggleExpand(record.id)}
                    >
                      {expanded ? tr('收起能力与诊断') : tr('能力与诊断 ({0}/{1})', [
                        record.grantedCapabilities.filter((c) => record.requestedCapabilities.includes(c)).length,
                        record.requestedCapabilities.length
                      ])}
                    </button>
                    {record.requestedCapabilities.length > 0 ? (
                      allGranted ? (
                        <button
                          type="button"
                          className="small-btn"
                          disabled={busy}
                          onClick={() => handleRevokeAll(record)}
                        >
                          {tr('撤回全部权限')}
                        </button>
                      ) : (
                        <button
                          type="button"
                          className="small-btn"
                          disabled={busy}
                          onClick={() => setConfirmGrantAllPlugin(record)}
                        >
                          {tr('授予全部权限')}
                        </button>
                      )
                    ) : null}
                  </div>
                  <button
                    type="button"
                    className="small-btn danger-btn"
                    disabled={busy}
                    onClick={() => {
                      setPurgeOnUninstall(false);
                      setConfirmUninstallPlugin(record);
                    }}
                  >
                    {tr('卸载')}
                  </button>
                </div>

                {expanded ? (
                  <div className="plugin-details">
                    <div className="plugin-details-section">
                      <div className="plugin-details-title">{tr('权限声明')}</div>
                      {record.requestedCapabilities.length === 0 ? (
                        <p className="right-hint">{tr('该插件未声明任何敏感能力。')}</p>
                      ) : (
                        <div className="plugin-cap-list">
                          {record.requestedCapabilities.map((cap) => {
                            const meta = PLUGIN_CAPABILITY_META[cap];
                            const granted = record.grantedCapabilities.includes(cap);
                            return (
                              <div className="plugin-cap-row" key={cap}>
                                <div className="plugin-cap-text">
                                  <div className="plugin-cap-name-row">
                                    <span>{meta ? tr(meta.label) : cap}</span>
                                    <span className="mono plugin-cap-id">{cap}</span>
                                    {meta?.risk === 'high' ? (
                                      <span className="plugin-badge tone-warn">{tr('高风险')}</span>
                                    ) : null}
                                  </div>
                                  {meta ? (
                                    <div className="plugin-cap-desc">{tr(meta.summary)}</div>
                                  ) : null}
                                </div>
                                <button
                                  type="button"
                                  role="switch"
                                  aria-checked={granted}
                                  aria-label={cap}
                                  className={`toggle${granted ? ' on' : ''}`}
                                  disabled={busy}
                                  onClick={() => handleToggleCapability(record, cap, granted)}
                                >
                                  <span className="toggle-knob" />
                                </button>
                              </div>
                            );
                          })}
                        </div>
                      )}
                    </div>

                    <div className="plugin-details-section">
                      <div className="plugin-details-title">{tr('运行诊断日志')}</div>
                      {diagnostics.length === 0 ? (
                        <p className="right-hint">{tr('暂无运行日志。')}</p>
                      ) : (
                        <div className="plugin-diag-log mono">
                          {diagnostics.map((line, index) => (
                            <div key={`${index}-${line.slice(0, 20)}`}>{line}</div>
                          ))}
                        </div>
                      )}
                    </div>
                  </div>
                ) : null}
              </div>
            );
          })}
        </div>
      )}

      {confirmGrantAllPlugin ? (
        <div className="modal-backdrop plugin-confirm-backdrop" role="presentation">
          <div className="dialog-card plugin-confirm-card" role="dialog" aria-modal="true">
            <div className="dialog-head">
              <h3>{tr('授予「{0}」全部权限？', [confirmGrantAllPlugin.name || confirmGrantAllPlugin.id])}</h3>
            </div>
            <p className="plugin-confirm-body">
              {tr('将允许此插件使用它声明的全部能力：{0}。若包含笔记写入、编辑器写入或 AI 推理能力，插件可修改笔记内容或调用已配置的模型。请只为信任的插件授予。', [
                confirmGrantAllPlugin.requestedCapabilities
                  .map((cap) => {
                    const meta = PLUGIN_CAPABILITY_META[cap];
                    return meta ? tr(meta.label) : cap;
                  })
                  .join('、')
              ])}
            </p>
            <div className="plugin-confirm-actions">
              <button
                type="button"
                className="small-btn"
                onClick={() => setConfirmGrantAllPlugin(null)}
              >
                {tr('取消')}
              </button>
              <button
                type="button"
                className="primary-btn"
                onClick={handleGrantAllConfirm}
              >
                {tr('确认授予')}
              </button>
            </div>
          </div>
        </div>
      ) : null}

      {confirmUninstallPlugin ? (
        <div className="modal-backdrop plugin-confirm-backdrop" role="presentation">
          <div className="dialog-card plugin-confirm-card" role="dialog" aria-modal="true">
            <div className="dialog-head">
              <h3>{tr('卸载「{0}」？', [confirmUninstallPlugin.name || confirmUninstallPlugin.id])}</h3>
            </div>
            <p className="plugin-confirm-body">
              {tr('将立即停用插件并从安装目录移除其代码文件。')}
            </p>
            <label className="plugin-uninstall-purge">
              <input
                type="checkbox"
                checked={purgeOnUninstall}
                onChange={(event) => setPurgeOnUninstall(event.target.checked)}
              />
              <span>{tr('同时删除该插件在工作区保存的配置与数据')}</span>
            </label>
            <div className="plugin-confirm-actions">
              <button
                type="button"
                className="small-btn"
                onClick={() => setConfirmUninstallPlugin(null)}
              >
                {tr('取消')}
              </button>
              <button
                type="button"
                className="primary-btn danger-fill"
                onClick={handleUninstallConfirm}
              >
                {tr('确认卸载')}
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
}

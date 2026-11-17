import React, { useEffect, useMemo, useState } from 'react';
import { useStore } from '../store/AppStore';
import type { AppSettings, ThemeMode, WorkspaceOpenMode } from '../../shared/types';
import {
  clampHistoryPolicy,
  formatBytes,
  type HistoryRetentionPolicy,
  type HistoryUsageSummary
} from '../../shared/noteHistory';
import { COMMANDS, DEFAULT_HOTKEYS } from '../core/commands';
import { DEFAULT_ACCENT, THEME_PRESETS, validAccent } from '../core/theme';
import { Icon } from './Icon';
import { PluginSettingsSection } from './PluginSettingsSection';

export type SettingsCategory =
  | 'about'
  | 'appearance'
  | 'interface'
  | 'editor'
  | 'data'
  | 'shortcuts'
  | 'plugins';

interface CategoryItem {
  id: SettingsCategory;
  label: string;
  icon: string;
  keywords: string;
}

const CATEGORIES: CategoryItem[] = [
  { id: 'about', label: '关于', icon: 'info', keywords: 'about 版本 语言 帮助 工作区 文件夹 数据 备份' },
  { id: 'appearance', label: '外观', icon: 'sun', keywords: 'appearance 主题 强调色 字体 预设 自定义' },
  { id: 'interface', label: '界面', icon: 'canvas', keywords: 'interface 功能区 侧栏 标签页 标题栏 缩放 比例 ribbon zoom' },
  { id: 'editor', label: '编辑器', icon: 'note', keywords: 'editor 缩进 视图 模式 标题 宽度 打开工作区' },
  { id: 'data', label: '文件与链接', icon: 'folder', keywords: 'files links data backup 双向链接 附件 路径 备份 zip json 导出 导入 索引 历史 快照' },
  { id: 'plugins', label: '插件', icon: 'spark', keywords: 'plugins 插件 扩展 权限 模型' },
  { id: 'shortcuts', label: '快捷键', icon: 'spark', keywords: 'shortcuts 快捷键 命令面板' }
];

function normalizeCategory(raw: string): SettingsCategory {
  if (
    raw === 'about' ||
    raw === 'appearance' ||
    raw === 'interface' ||
    raw === 'editor' ||
    raw === 'data' ||
    raw === 'shortcuts' ||
    raw === 'plugins'
  ) {
    return raw;
  }
  if (raw === 'hotkeys') return 'shortcuts';
  if (raw === 'files') return 'data';
  if (raw === 'workspace') return 'editor';
  return 'about';
}

function formatKeyCombo(event: React.KeyboardEvent): string | null {
  if (event.key === 'Control' || event.key === 'Shift' || event.key === 'Alt' || event.key === 'Meta') {
    return null;
  }
  const parts: string[] = [];
  if (event.ctrlKey || event.metaKey) parts.push('Ctrl');
  if (event.altKey) parts.push('Alt');
  if (event.shiftKey) parts.push('Shift');
  const rawKey = event.key;
  const isFKey = /^F([1-9]|1[0-2])$/i.test(rawKey);
  if (parts.length === 0 && !isFKey) {
    return null;
  }
  let keyLabel = rawKey.length === 1 ? rawKey.toUpperCase() : rawKey;
  if (rawKey === ' ') keyLabel = 'Space';
  if (rawKey === 'ArrowLeft') keyLabel = '←';
  if (rawKey === 'ArrowRight') keyLabel = '→';
  if (rawKey === 'ArrowUp') keyLabel = '↑';
  if (rawKey === 'ArrowDown') keyLabel = '↓';
  parts.push(keyLabel);
  return parts.join('+');
}

function SettingRow({
  title,
  description,
  control
}: {
  title: string;
  description?: string;
  control: React.ReactNode;
}): JSX.Element {
  return (
    <div className="setting-row">
      <div className="setting-copy">
        <div className="setting-title">{title}</div>
        {description ? <div className="setting-desc">{description}</div> : null}
      </div>
      <div className="setting-control">{control}</div>
    </div>
  );
}

function Toggle({
  checked,
  onChange,
  label
}: {
  checked: boolean;
  onChange: (next: boolean) => void;
  label?: string;
}): JSX.Element {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-label={label}
      className={`toggle ${checked ? 'on' : ''}`}
      onClick={() => onChange(!checked)}
    >
      <span className="toggle-knob" />
    </button>
  );
}

function Segmented<T extends string>({
  options,
  value,
  onChange
}: {
  options: Array<{ value: T; label: string }>;
  value: T;
  onChange: (next: T) => void;
}): JSX.Element {
  return (
    <div className="settings-segmented">
      {options.map((opt) => (
        <button
          key={opt.value}
          type="button"
          className={`settings-segmented-btn ${opt.value === value ? 'active' : ''}`}
          aria-pressed={opt.value === value}
          onClick={() => onChange(opt.value)}
        >
          {opt.label}
        </button>
      ))}
    </div>
  );
}

export function SettingsDialog(): JSX.Element {
  const { state, derived, actions } = useStore();
  const { tr } = derived;
  const category = normalizeCategory(state.settingsCategory);
  const setCategory = (next: SettingsCategory): void => {
    actions.setSettingsCategory(next);
  };
  const [searchQuery, setSearchQuery] = useState('');
  const [customHex, setCustomHex] = useState(state.settings.accent || DEFAULT_ACCENT);
  const [hexError, setHexError] = useState('');
  const [hotkeyQuery, setHotkeyQuery] = useState('');
  const [recordingCommandId, setRecordingCommandId] = useState('');
  const [hotkeyNotice, setHotkeyNotice] = useState('');
  const [historyUsage, setHistoryUsage] = useState<HistoryUsageSummary>({
    noteCount: 0,
    revisionCount: 0,
    totalBytes: 0
  });
  const [historyBusy, setHistoryBusy] = useState(false);

  const policy = clampHistoryPolicy(state.settings.historyPolicy);

  useEffect(() => {
    setCustomHex(state.settings.accent || DEFAULT_ACCENT);
  }, [state.settings.accent]);

  useEffect(() => {
    if (!state.settingsOpen) {
      setRecordingCommandId('');
      setHotkeyNotice('');
      return;
    }
    setSearchQuery('');
    setHotkeyQuery('');
    void window.lexi?.history.usage().then(setHistoryUsage).catch(() => {});
  }, [state.settingsOpen]);

  const updatePolicy = async (patchPolicy: Partial<HistoryRetentionPolicy>): Promise<void> => {
    const nextPolicy = clampHistoryPolicy({ ...policy, ...patchPolicy });
    actions.updateSettings({ historyPolicy: nextPolicy });
    if (window.lexi?.history) {
      setHistoryBusy(true);
      try {
        const res = await window.lexi.history.prune(nextPolicy);
        setHistoryUsage(res.summary);
      } finally {
        setHistoryBusy(false);
      }
    }
  };

  const cleanupHistoryNow = async (): Promise<void> => {
    if (!window.lexi?.history) return;
    setHistoryBusy(true);
    try {
      const res = await window.lexi.history.prune(policy);
      setHistoryUsage(res.summary);
      actions.showToast(`清理完成，已移除 ${res.removedCount} 个过期或超额快照`);
    } finally {
      setHistoryBusy(false);
    }
  };

  const applyCustomHex = (raw: string): void => {
    const formatted = raw.trim().startsWith('#') ? raw.trim().toUpperCase() : `#${raw.trim().toUpperCase()}`;
    if (!validAccent(formatted)) {
      setHexError(tr('请输入 6 位十六进制颜色，如 #6E44D9'));
      return;
    }
    setHexError('');
    setCustomHex(formatted);
    actions.updateSettings({ accent: formatted, paletteMode: 'custom' });
  };

  const filteredCategories = useMemo(() => {
    const q = searchQuery.trim().toLowerCase();
    if (!q) return CATEGORIES;
    return CATEGORIES.filter(
      (item) =>
        tr(item.label).toLowerCase().includes(q) || item.keywords.toLowerCase().includes(q)
    );
  }, [searchQuery, tr]);

  const filteredCommands = useMemo(() => {
    const q = hotkeyQuery.trim().toLowerCase();
    if (!q) return COMMANDS;
    return COMMANDS.filter((cmd) => {
      const binding = state.settings.hotkeys?.[cmd.id] ?? cmd.shortcut ?? '';
      return (
        tr(cmd.title).toLowerCase().includes(q) ||
        cmd.title.toLowerCase().includes(q) ||
        cmd.id.toLowerCase().includes(q) ||
        binding.toLowerCase().includes(q)
      );
    });
  }, [hotkeyQuery, state.settings.hotkeys, tr]);

  const activeCategory = filteredCategories.some((c) => c.id === category)
    ? category
    : (filteredCategories[0]?.id ?? 'about');

  const s = state.settings;
  const activeVault = derived.activeVault;

  const renderWorkspaceOpenSection = (): JSX.Element => (
    <>
      <div className="settings-group-header">{tr('打开工作区')}</div>
      <div className="settings-card">
        <SettingRow
          title={tr('选择工作区时不再提示')}
          description={tr('该开关对所有工作区生效，不按工作区保存；关闭后会重新显示询问。')}
          control={
            <Toggle
              label={tr('选择工作区时不再提示')}
              checked={s.workspacePromptSuppressed}
              onChange={(v) => actions.setWorkspacePromptSuppressed(v)}
            />
          }
        />
        <div className="settings-divider" />
        <SettingRow
          title={tr('默认打开方式')}
          description={tr('当工作区设为“每次询问”且已关闭提示时使用。')}
          control={
            <Segmented<AppSettings['workspaceDefaultOpenMode']>
              value={s.workspaceDefaultOpenMode}
              onChange={(v) => actions.setWorkspaceDefaultOpenMode(v)}
              options={[
                { value: 'current', label: tr('当前窗口') },
                { value: 'new', label: tr('新窗口') }
              ]}
            />
          }
        />
        <div className="settings-divider" />
        <div className="setting-row" style={{ flexDirection: 'column', alignItems: 'stretch', gap: 8 }}>
          <div className="setting-copy">
            <div className="setting-title">{tr('每个工作区的打开方式')}</div>
            <div className="setting-desc">
              {tr('设置绑定工作区，而不是整个软件。打开方式保存在工作区本身，归档、备份和恢复会一并保留。')}
            </div>
          </div>
          <div className="workspace-mode-list">
            {state.vaults.map((vault) => (
              <div className="workspace-mode-row" key={vault.id}>
                <span className="workspace-mode-name">{vault.name}</span>
                <select
                  className="select"
                  value={vault.openMode ?? 'ask'}
                  aria-label={tr('{0} 的打开方式', [vault.name])}
                  onChange={(e) =>
                    actions.setVaultOpenMode(vault.id, e.target.value as WorkspaceOpenMode)
                  }
                >
                  <option value="ask">{tr('每次询问')}</option>
                  <option value="current">{tr('在当前窗口打开')}</option>
                  <option value="new">{tr('在新窗口打开')}</option>
                </select>
              </div>
            ))}
          </div>
        </div>
      </div>
    </>
  );

  return (
    <>
        <div className="settings-topbar settings-content-head">
          <div className="settings-topbar-title">{tr('设置')}</div>
          <button
            type="button"
            className="settings-topbar-close icon-btn"
            onClick={actions.closeSettings}
            aria-label={tr('关闭')}
            title={tr('关闭')}
          >
            {tr('关闭')}
          </button>
        </div>

        <div className="settings-body">
          <aside className="settings-rail">
            <div className="settings-search">
              <Icon name="search" size={14} muted />
              <input
                type="text"
                placeholder={tr('搜索设置...')}
                value={searchQuery}
                aria-label={tr('搜索设置...')}
                onChange={(e) => setSearchQuery(e.target.value)}
              />
              {searchQuery ? (
                <button type="button" className="settings-search-clear" aria-label={tr('清空搜索')} onClick={() => setSearchQuery('')}>×</button>
              ) : null}
            </div>

            <div className="settings-rail-label">{tr('选项')}</div>
            <div className="settings-categories">
              {filteredCategories.map((item) => {
                const active = activeCategory === item.id;
                return (
                  <button
                    key={item.id}
                    type="button"
                    className={`settings-category ${active ? 'active' : ''}`}
                    aria-current={active ? 'page' : undefined}
                    onClick={() => setCategory(item.id)}
                  >
                    <Icon name={item.icon} size={16} muted={!active} />
                    <span>{tr(item.label)}</span>
                  </button>
                );
              })}
            </div>
          </aside>

          <main className="settings-content">
            <div className="settings-scroll" key={activeCategory}>
              <div className="settings-group">
            {activeCategory === 'about' ? (
              <div className="settings-page">
                <h2 className="settings-page-title">{tr('关于')}</h2>
                <div className="settings-card">
                  <SettingRow
                    title={tr('版本')}
                    control={<span className="settings-version">{state.runtime?.appVersion || '2.0.1'}</span>}
                  />
                  <div className="settings-divider" />
                  <SettingRow
                    title={tr('语言')}
                    control={
                      <select className="select" value={s.language} aria-label={tr('语言')}
                        onChange={(event) => actions.updateSettings({ language: event.target.value as AppSettings['language'] })}>
                        <option value="zh-Hans">简体中文</option>
                        <option value="en">English</option>
                      </select>
                    }
                  />
                  <div className="settings-divider" />
                  <SettingRow
                    title={tr('使用帮助')}
                    control={
                      <button
                        type="button"
                        className="settings-btn-soft"
                        onClick={() => {
                          actions.closeSettings();
                          actions.setHelpOpen(true);
                        }}
                      >
                        {tr('打开')}
                      </button>
                    }
                  />
                </div>
                <div className="settings-group-header">{tr('数据与备份')}</div>
                <div className="settings-card padded">
                  <div className="settings-storage-info">
                    <Icon name="folder" size={20} />
                    <div className="setting-copy">
                      <div className="setting-title settings-storage-path" title={activeVault?.folderUri}>
                        {tr('工作区文件夹：{0}', [activeVault?.folderUri || activeVault?.name || tr('默认工作区')])}
                      </div>
                      <div className="setting-desc">{tr('笔记 (.md)、思维导图与白板均直接保存在此工作区文件夹中。')}</div>
                    </div>
                  </div>
                  <button type="button" className="settings-btn-soft settings-storage-button" onClick={() => void actions.chooseWorkspaceFolder()}>
                    {tr('更改工作区文件夹')}
                  </button>
                </div>
              </div>
            ) : null}

            {activeCategory === 'appearance' ? (
              <div className="settings-page">
                <h2 className="settings-page-title">{tr('外观')}</h2>

                <div className="settings-card">
                  <div className="settings-theme-block">
                    <div className="setting-copy">
                      <div className="setting-title">{tr('基础颜色')}</div>
                      <div className="setting-desc">{tr('设置应用的明暗外观。')}</div>
                    </div>
                    <Segmented<ThemeMode>
                      value={s.theme}
                      onChange={(theme) => actions.updateSettings({ theme })}
                      options={[
                        { value: 'system', label: tr('跟随系统') },
                        { value: 'light', label: tr('浅色') },
                        { value: 'dark', label: tr('深色') }
                      ]}
                    />
                  </div>
                  <div className="settings-divider" />
                  <div className="settings-theme-block">
                    <div className="settings-theme-heading">
                      <div className="setting-title">{tr('全局色调')}</div>
                      <span>{tr(s.paletteMode === 'original' ? '原配色调' : s.paletteMode === 'custom' ? '自定义' :
                        THEME_PRESETS.find((preset) => preset.color.toUpperCase() === s.accent.toUpperCase())?.label || '主题色')}</span>
                    </div>
                    <div className="setting-desc">{tr('统一调整背景、侧栏、按钮和笔记链接，选择后自动保存。')}</div>
                    <div className="settings-theme-preview" aria-label={tr('主题预览')}>
                      <div className="settings-theme-preview-sidebar">
                        <strong>{tr('知萤')}</strong>
                        <span className="selected">{tr('笔记')}</span>
                        <span>{tr('文件夹')}</span>
                      </div>
                      <div className="settings-theme-preview-page">
                        <strong>{tr('主题预览')} <span>●</span></strong>
                        <div className="settings-divider" />
                        <span>{tr('让灵感拥有你的颜色')}</span>
                        <span className="settings-theme-preview-link">[[ {tr('双向链接')} ]]</span>
                      </div>
                    </div>
                    <button
                      type="button"
                      className={`theme-preset-pill settings-original-theme ${s.paletteMode === 'original' ? 'active' : ''}`}
                      aria-pressed={s.paletteMode === 'original'}
                      onClick={() => actions.updateSettings({ paletteMode: 'original', accent: DEFAULT_ACCENT })}
                    >
                      <span className="theme-preset-dot" style={{ backgroundColor: DEFAULT_ACCENT }} />
                      <span>{tr('原配色调')}</span>
                      {s.paletteMode === 'original' ? <span className="settings-theme-check">✓</span> : null}
                    </button>
                    <div className="theme-preset-grid">
                      {THEME_PRESETS.map((preset) => {
                        const isSelected = s.paletteMode === 'preset' && s.accent.toUpperCase() === preset.color.toUpperCase();
                        return (
                          <button
                            key={preset.color}
                            type="button"
                            className={`theme-preset-pill ${isSelected ? 'active' : ''}`}
                            aria-pressed={isSelected}
                            onClick={() => actions.updateSettings({ accent: preset.color, paletteMode: 'preset' })}
                          >
                            <span className="theme-preset-dot" style={{ backgroundColor: preset.color }} />
                            <span>{tr(preset.label)}</span>
                          </button>
                        );
                      })}
                    </div>
                    <div className="setting-title">{tr('自定义')}</div>
                    <div className="custom-color-bar">
                      <input
                        type="color"
                        value={validAccent(customHex) ? customHex : s.accent}
                        aria-label={tr('自定义主题色')}
                        onChange={(e) => applyCustomHex(e.target.value)}
                        style={{ width: 32, height: 30, padding: 0, border: 'none', background: 'transparent', cursor: 'pointer' }}
                      />
                      <input
                        type="text"
                        className="custom-hex-input"
                        value={customHex}
                        placeholder="#6E44D9"
                        aria-label={tr('输入十六进制颜色，按回车或离开输入框即可保存。')}
                        onChange={(e) => {
                          setCustomHex(e.target.value);
                          setHexError('');
                        }}
                        onBlur={() => applyCustomHex(customHex)}
                        onKeyDown={(e) => {
                          if (e.key === 'Enter') applyCustomHex(customHex);
                        }}
                      />
                      <button
                        type="button"
                        className="settings-btn-soft"
                        onClick={() => applyCustomHex(customHex)}
                      >
                        {tr('应用')}
                      </button>
                      <button
                        type="button"
                        className="settings-btn-inset"
                        onClick={() => {
                          setCustomHex(DEFAULT_ACCENT);
                          setHexError('');
                          actions.updateSettings({ accent: DEFAULT_ACCENT, paletteMode: 'original' });
                        }}
                      >
                        {tr('重置')}
                      </button>
                    </div>
                    {hexError ? <div className="settings-note" style={{ color: 'var(--error)' }}>{hexError}</div> : null}
                  </div>
                </div>

                <div className="settings-group-header">{tr('字体大小')}</div>
                <div className="settings-card">
                  <SettingRow
                    title={tr('字体大小')}
                    description={tr('调整笔记编辑与预览中的文字大小。')}
                    control={
                      <div className="range-row">
                        <input
                          type="range"
                          min={12}
                          max={26}
                          value={s.fontSize}
                          onChange={(e) => actions.updateSettings({ fontSize: Number(e.target.value) })}
                        />
                        <span className="range-value">{s.fontSize}px</span>
                      </div>
                    }
                  />
                </div>

              </div>
            ) : null}

            {activeCategory === 'interface' ? (
              <div className="settings-page">
                <h2 className="settings-page-title">{tr('界面')}</h2>
                <div className="settings-card">
                  <SettingRow
                    title={tr('显示标签页标题栏')}
                    description={tr('在每个标签页上方显示标题栏。')}
                    control={
                      <Toggle
                        label={tr('显示标签页标题栏')}
                        checked={s.showTabHeaders}
                        onChange={(v) => actions.updateSettings({ showTabHeaders: v })}
                      />
                    }
                  />
                  <div className="settings-divider" />
                  <SettingRow
                    title={tr('显示功能区')}
                    description={tr('显示窗口最左侧的功能区，以便快速执行命令。')}
                    control={
                      <Toggle
                        label={tr('显示功能区')}
                        checked={s.showRibbon}
                        onChange={(v) => actions.updateSettings({ showRibbon: v })}
                      />
                    }
                  />
                  <div className="settings-divider" />
                  <SettingRow
                    title={tr('侧栏宽度')}
                    description={tr('拖动侧栏边缘可随时调整；这里可以恢复默认宽度。')}
                    control={
                      <button
                        type="button"
                        className="settings-btn-inset"
                        onClick={() => actions.updateSettings({ sidebarWidth: 244, rightSidebarWidth: 280 })}
                      >
                        {tr('恢复默认')}
                      </button>
                    }
                  />
                </div>
                <div className="settings-group-header">{tr('高级')}</div>
                <div className="settings-card">
                  <SettingRow
                    title={tr('缩放比例')}
                    description={tr('控制应用程序的整体缩放比例。')}
                    control={
                      <div className="range-row">
                        <input
                          type="range"
                          min={75}
                          max={150}
                          step={5}
                          value={s.zoom || 100}
                          onChange={(e) => actions.updateSettings({ zoom: Number(e.target.value) })}
                        />
                        <span className="range-value">{s.zoom || 100}%</span>
                      </div>
                    }
                  />
                </div>
              </div>
            ) : null}

            {activeCategory === 'editor' ? (
              <div className="settings-page">
                <h2 className="settings-page-title">{tr('编辑器')}</h2>

                <div className="settings-scope-banner">
                  <Icon name="info" size={14} />
                  <span>{tr('编辑器设置仅应用于工作区「{0}」。', [activeVault?.name ?? tr('个人知识库')])}</span>
                </div>

                <div className="settings-group-header">{tr('默认视图与模式')}</div>
                <div className="settings-card">
                  <SettingRow
                    title={tr('新标签页的默认视图')}
                    description={tr('设置新打开笔记的默认视图。')}
                    control={
                      <Segmented<AppSettings['editorDefaultView']>
                        value={s.editorDefaultView}
                        onChange={(v) => actions.updateSettings({ editorDefaultView: v })}
                        options={[
                          { value: 'live', label: tr('编辑视图') },
                          { value: 'reading', label: tr('阅读视图') }
                        ]}
                      />
                    }
                  />
                  <div className="settings-divider" />
                  <SettingRow
                    title={tr('默认编辑模式')}
                    description={tr('源码模式显示完整 Markdown；实时预览按块就地编辑。')}
                    control={
                      <Segmented<'live' | 'source'>
                        value={s.editorDefaultMode}
                        onChange={(v) => actions.updateSettings({ editorDefaultMode: v, editorDefaultView: v })}
                        options={[
                          { value: 'live', label: tr('实时预览') },
                          { value: 'source', label: tr('源码模式') }
                        ]}
                      />
                    }
                  />
                </div>

                <div className="settings-group-header">{tr('显示')}</div>
                <div className="settings-card">
                  <SettingRow
                    title={tr('限制行宽')}
                    description={tr('将正文宽度限制在便于阅读的范围内。')}
                    control={
                      <Toggle
                        label={tr('限制行宽')}
                        checked={s.editorLimitWidth}
                        onChange={(v) => actions.updateSettings({ editorLimitWidth: v })}
                      />
                    }
                  />
                  <div className="settings-divider" />
                  <SettingRow
                    title={tr('页面内标题')}
                    description={tr('在正文顶部显示可编辑的大标题。')}
                    control={
                      <Toggle
                        label={tr('页面内标题')}
                        checked={s.editorShowTitle}
                        onChange={(v) => actions.updateSettings({ editorShowTitle: v })}
                      />
                    }
                  />
                  <div className="settings-divider" />
                  <SettingRow
                    title={tr('视图状态')}
                    description={tr('在底部状态栏显示当前视图模式与字数。')}
                    control={
                      <Toggle
                        label={tr('视图状态')}
                        checked={s.editorViewStatus}
                        onChange={(v) => actions.updateSettings({ editorViewStatus: v })}
                      />
                    }
                  />
                </div>

                {renderWorkspaceOpenSection()}
              </div>
            ) : null}

            {activeCategory === 'data' ? (
              <div className="settings-page">
                <h2 className="settings-page-title">{tr('文件与链接')}</h2>

                <div className="settings-group-header">{tr('文件存储规范')}</div>
                <div className="settings-card">
                  <SettingRow
                    title={tr('Markdown 文档')}
                    description={tr('直接以 .md 文件保存在工作区文件夹中')}
                    control={<span className="settings-badge-muted">.md</span>}
                  />
                  <div className="settings-divider" />
                  <SettingRow
                    title={tr('思维导图')}
                    description={tr('保存在工作区 思维导图/ 目录下')}
                    control={<span className="settings-badge-muted">.mindmap.json</span>}
                  />
                  <div className="settings-divider" />
                  <SettingRow
                    title={tr('自由白板')}
                    description={tr('保存在工作区 白板/ 目录下')}
                    control={<span className="settings-badge-muted">.canvas.json</span>}
                  />
                  <div className="settings-divider" />
                  <SettingRow
                    title={tr('Wiki 双向链接')}
                    description={tr('支持 [[文档标题]] 语法并自动建立反向引用索引')}
                    control={<span className="settings-badge-muted">[[Link]]</span>}
                  />
                </div>


                <div className="settings-group-header">{tr('工作区归档 (.zip)')}</div>
                <div className="settings-card">
                  <SettingRow
                    title={tr('导出工作区压缩包')}
                    description={tr('打包当前工作区全部 .md 笔记、思维导图与白板文件为 .zip')}
                    control={
                      <button
                        type="button"
                        className="settings-btn-primary"
                        onClick={() => void actions.exportWorkspaceZip()}
                      >
                        {tr('导出 .zip')}
                      </button>
                    }
                  />
                  <div className="settings-divider" />
                  <SettingRow
                    title={tr('从压缩包导入工作区')}
                    description={tr('选择 .zip 归档并解压保存到指定工作区文件夹，随后自动打开')}
                    control={
                      <button
                        type="button"
                        className="settings-btn-inset"
                        onClick={() => void actions.importWorkspaceZip()}
                      >
                        {tr('导入 .zip…')}
                      </button>
                    }
                  />
                </div>

                <div className="settings-group-header">{tr('设置与插件备份 (.json)')}</div>
                <div className="settings-card">
                  <SettingRow
                    title={tr('导出设置与插件 (.json)')}
                    description={tr('导出外观、编辑器、工作区偏好及已安装插件清单为 JSON')}
                    control={
                      <button
                        type="button"
                        className="settings-btn-soft"
                        onClick={() => void actions.exportSettingsPlugins()}
                      >
                        {tr('导出 .json')}
                      </button>
                    }
                  />
                  <div className="settings-divider" />
                  <SettingRow
                    title={tr('导入设置与插件 (.json)')}
                    description={tr('从导出的 .json 恢复应用偏好设置与插件配置')}
                    control={
                      <button
                        type="button"
                        className="settings-btn-inset"
                        onClick={() => void actions.importSettingsPlugins()}
                      >
                        {tr('导入 .json…')}
                      </button>
                    }
                  />
                </div>

                <div className="settings-group-header">{tr('索引维护')}</div>
                <div className="settings-card">
                  <SettingRow
                    title={tr('重建索引')}
                    description={tr('从当前工作区文件夹重新扫描笔记、思维导图、白板与双向链接')}
                    control={
                      <button
                        type="button"
                        className="settings-btn-inset"
                        onClick={() => void actions.rebuildIndex()}
                      >
                        {tr('重建索引')}
                      </button>
                    }
                  />
                </div>

                <div className="settings-group-header">{tr('版本历史与自动清理')}</div>
                <div className="settings-card">
                  <SettingRow
                    title={tr('当前快照占用')}
                    description={tr('已保留 {0} 个快照（涉及 {1} 篇笔记），总计 {2}', [
                      historyUsage.revisionCount,
                      historyUsage.noteCount,
                      formatBytes(historyUsage.totalBytes)
                    ])}
                    control={
                      <button
                        type="button"
                        className="settings-btn-inset"
                        disabled={historyBusy}
                        onClick={() => void cleanupHistoryNow()}
                      >
                        {tr('立即按规则清理')}
                      </button>
                    }
                  />
                  <div className="settings-divider" />
                  <SettingRow
                    title={tr('快照保留天数')}
                    description={tr('超过所选天数的旧历史快照会在保存和清理时自动移除')}
                    control={
                      <Segmented
                        value={String(policy.maxAgeDays)}
                        options={[
                          { value: '7', label: tr('7 天') },
                          { value: '30', label: tr('30 天') },
                          { value: '90', label: tr('90 天') }
                        ]}
                        onChange={(v) => void updatePolicy({ maxAgeDays: Number(v) })}
                      />
                    }
                  />
                  <div className="settings-divider" />
                  <SettingRow
                    title={tr('单篇笔记快照上限')}
                    description={tr('每篇笔记最多保留的历史快照数量')}
                    control={
                      <Segmented
                        value={String(policy.maxCountPerNote)}
                        options={[
                          { value: '20', label: tr('20 条') },
                          { value: '30', label: tr('30 条') },
                          { value: '50', label: tr('50 条') }
                        ]}
                        onChange={(v) => void updatePolicy({ maxCountPerNote: Number(v) })}
                      />
                    }
                  />
                  <div className="settings-divider" />
                  <SettingRow
                    title={tr('历史快照总存储上限')}
                    description={tr('当全部历史快照总容量超限时，自动从最旧快照开始淘汰')}
                    control={
                      <Segmented
                        value={String(Math.round(policy.maxTotalBytes / (1024 * 1024)))}
                        options={[
                          { value: '20', label: '20 MB' },
                          { value: '50', label: '50 MB' },
                          { value: '100', label: '100 MB' }
                        ]}
                        onChange={(v) => void updatePolicy({ maxTotalBytes: Number(v) * 1024 * 1024 })}
                      />
                    }
                  />
                </div>
              </div>
            ) : null}

            {activeCategory === 'shortcuts' ? (
              <div className="settings-page">
                <h2 className="settings-page-title">{tr('快捷键')}</h2>
                <p className="settings-note" style={{ margin: '0 0 8px' }}>
                  {tr('搜索命令，点击「+」后按下组合键；Esc 取消录制。')}
                </p>

                <div className="settings-search" style={{ marginBottom: 10 }}>
                  <Icon name="search" size={14} muted />
                  <input
                    type="text"
                    placeholder={tr('搜索命令或快捷键')}
                    value={hotkeyQuery}
                    onChange={(e) => setHotkeyQuery(e.target.value)}
                  />
                </div>

                {hotkeyNotice ? (
                  <div className="settings-scope-banner" style={{ marginBottom: 8 }}>
                    <span>{hotkeyNotice}</span>
                  </div>
                ) : null}

                <div className="settings-card">
                  {filteredCommands.map((cmd, idx) => {
                    const currentKey = s.hotkeys?.[cmd.id] ?? cmd.shortcut ?? '';
                    const isRecording = recordingCommandId === cmd.id;
                    const defaultKey = DEFAULT_HOTKEYS[cmd.id] ?? '';
                    return (
                      <React.Fragment key={cmd.id}>
                        {idx > 0 ? <div className="settings-divider" /> : null}
                        <div className="setting-row">
                          <div className="setting-copy">
                            <div className="setting-title">{tr(cmd.title)}</div>
                            <div className="setting-desc">{tr(cmd.group)}</div>
                          </div>
                          <div className="setting-control">
                            {isRecording ? (
                              <button
                                type="button"
                                className="settings-pill-btn"
                                autoFocus
                                onBlur={() => setRecordingCommandId('')}
                                onKeyDown={(e) => {
                                  e.preventDefault();
                                  e.stopPropagation();
                                  if (e.key === 'Escape') {
                                    setRecordingCommandId('');
                                    return;
                                  }
                                  const combo = formatKeyCombo(e);
                                  if (!combo) {
                                    setHotkeyNotice(tr('请同时按下修饰键（Ctrl / Alt / Shift）与按键，或直接按 F1–F12。'));
                                    return;
                                  }
                                  const conflictCmd = COMMANDS.find(
                                    (other) =>
                                      other.id !== cmd.id &&
                                      (s.hotkeys?.[other.id] ?? other.shortcut ?? '').toLowerCase() ===
                                        combo.toLowerCase()
                                  );
                                  if (conflictCmd) {
                                    setHotkeyNotice(`${tr('快捷键已被占用：')}${tr(conflictCmd.title)} (${combo})`);
                                    return;
                                  }
                                  actions.updateSettings({
                                    hotkeys: { ...(s.hotkeys ?? {}), [cmd.id]: combo }
                                  });
                                  setHotkeyNotice(`${tr('已绑定')} ${tr(cmd.title)} → ${combo}`);
                                  setRecordingCommandId('');
                                }}
                              >
                                {tr('按下快捷键…')}
                              </button>
                            ) : (
                              <>
                                {currentKey ? (
                                  <kbd className="kbd">{currentKey}</kbd>
                                ) : (
                                  <span className="settings-badge-muted">{tr('未设置')}</span>
                                )}
                                <button
                                  type="button"
                                  className="settings-btn-soft"
                                  style={{ height: 28, padding: '0 10px' }}
                                  title={tr('添加快捷键')}
                                  onClick={() => {
                                    setHotkeyNotice('');
                                    setRecordingCommandId(cmd.id);
                                  }}
                                >
                                  +
                                </button>
                                {currentKey !== defaultKey ? (
                                  <button
                                    type="button"
                                    className="settings-btn-inset"
                                    style={{ height: 28, padding: '0 10px' }}
                                    onClick={() => {
                                      const next = { ...(s.hotkeys ?? {}) };
                                      if (defaultKey) next[cmd.id] = defaultKey;
                                      else delete next[cmd.id];
                                      actions.updateSettings({ hotkeys: next });
                                    }}
                                  >
                                    {tr('重置')}
                                  </button>
                                ) : null}
                              </>
                            )}
                          </div>
                        </div>
                      </React.Fragment>
                    );
                  })}
                </div>
              </div>
            ) : null}

            {activeCategory === 'plugins' ? (
              <div className="settings-page">
                <PluginSettingsSection />
              </div>
            ) : null}
              </div>
            </div>
          </main>
        </div>
    </>
  );
}

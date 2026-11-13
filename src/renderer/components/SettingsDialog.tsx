import React, { useMemo, useState } from 'react';
import { useStore } from '../store/AppStore';
import type { AppSettings, ThemeMode } from '../../shared/types';
import { Icon } from './Icon';
import { PluginSettingsSection } from './PluginSettingsSection';

const ACCENT_SWATCHES = ['#6E44D9', '#2563EB', '#16A34A', '#D97706', '#DC2626'];

export type SettingsCategory =
  | 'about'
  | 'appearance'
  | 'workspace'
  | 'editor'
  | 'files'
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
  { id: 'about', label: '关于', icon: 'info', keywords: 'about 版本 隐私 本地' },
  { id: 'appearance', label: '外观', icon: 'sun', keywords: 'appearance 主题 强调色 字体 语言 侧边栏 标签栏' },
  { id: 'workspace', label: '工作区', icon: 'folder', keywords: 'workspace 工作区 文件夹 默认打开方式' },
  { id: 'editor', label: '编辑器', icon: 'note', keywords: 'editor 缩进 视图 模式 标题 宽度' },
  { id: 'files', label: '文件与链接', icon: 'link', keywords: 'files links 双向链接 附件 路径' },
  { id: 'data', label: '数据与备份', icon: 'export', keywords: 'data backup zip json 导出 导入 索引' },
  { id: 'shortcuts', label: '快捷键', icon: 'spark', keywords: 'shortcuts 快捷键 命令面板' },
  { id: 'plugins', label: '插件', icon: 'shield', keywords: 'plugins 插件 扩展 权限' }
];

const SHORTCUTS: Array<[string, string]> = [
  ['Ctrl+N', '新建文档'],
  ['Ctrl+K', '命令面板'],
  ['Ctrl+F', '全局搜索'],
  ['Ctrl+Shift+T', '打开标签管理器'],
  ['Ctrl+G', '知识图谱'],
  ['Ctrl+,', '打开设置'],
  ['Ctrl+W', '关闭当前标签'],
  ['Ctrl+S', '立即保存'],
  ['Ctrl+B / I / K', '加粗 / 斜体 / 链接'],
  ['Ctrl+1 / 2 / 3', '一级至三级标题'],
  ['Ctrl+Z / Y', '撤销 / 重做'],
  ['Ctrl+= / -', '放大 / 缩小']
];

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
  onChange
}: {
  checked: boolean;
  onChange: (next: boolean) => void;
}): JSX.Element {
  return (
    <button
      type="button"
      className={`toggle ${checked ? 'on' : ''}`}
      aria-pressed={checked}
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
          onClick={() => onChange(opt.value)}
        >
          {opt.label}
        </button>
      ))}
    </div>
  );
}

export function SettingsDialog(): JSX.Element | null {
  const { state, derived, actions } = useStore();
  const { tr } = derived;
  const [category, setCategory] = useState<SettingsCategory>('appearance');
  const [searchQuery, setSearchQuery] = useState('');

  const filteredCategories = useMemo(() => {
    const q = searchQuery.trim().toLowerCase();
    if (!q) return CATEGORIES;
    return CATEGORIES.filter(
      (item) =>
        tr(item.label).toLowerCase().includes(q) || item.keywords.toLowerCase().includes(q)
    );
  }, [searchQuery, tr]);

  if (!state.settingsOpen) return null;

  const activeCategory = filteredCategories.some((c) => c.id === category)
    ? category
    : (filteredCategories[0]?.id ?? 'appearance');

  const s = state.settings;
  const activeVault = derived.activeVault;

  return (
    <div
      className="modal-backdrop"
      onClick={actions.closeSettings}
      role="dialog"
      aria-modal="true"
    >
      <div className="settings-window" onClick={(e) => e.stopPropagation()}>
        <div className="settings-topbar">
          <div className="settings-topbar-title" style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <Icon name="sun" size={16} />
            <span>{tr('设置')}</span>
          </div>
          <button
            type="button"
            className="settings-topbar-close"
            onClick={actions.closeSettings}
            aria-label={tr('关闭')}
            title={tr('关闭')}
          >
            ✕
          </button>
        </div>

        <div className="settings-body">
          <aside className="settings-rail">
            <div className="settings-search">
              <Icon name="search" size={14} muted />
              <input
                type="text"
                placeholder={tr('搜索设置')}
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
              />
            </div>

            <div className="settings-categories">
              {filteredCategories.map((item) => {
                const active = activeCategory === item.id;
                return (
                  <button
                    key={item.id}
                    type="button"
                    className={`settings-category ${active ? 'active' : ''}`}
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
            <div className="settings-scroll">
              <div className="settings-group">
            {activeCategory === 'about' ? (
              <div className="settings-page">
                <h2 className="settings-page-title">{tr('关于')}</h2>
                <div className="settings-card">
                  <div className="settings-about-hero">
                    <div className="settings-about-logo">L</div>
                    <div>
                      <div className="settings-about-name">LexiNote</div>
                      <div className="settings-about-ver">v2.0.1 · Local-First Knowledge Workspace</div>
                    </div>
                  </div>
                </div>

                <div className="settings-group-header">{tr('应用信息')}</div>
                <div className="settings-card">
                  <SettingRow
                    title={tr('本地优先架构')}
                    description={tr('所有 Markdown 笔记、思维导图与自由白板均以标准文件存储在工作区文件夹中。')}
                    control={<span className="settings-badge-muted">{tr('离线可用')}</span>}
                  />
                  <div className="settings-divider" />
                  <SettingRow
                    title={tr('隐私与数据边界')}
                    description={tr('不上传个人笔记内容；插件运行在无网络沙箱中并显式授予权限。')}
                    control={<span className="settings-badge-muted">{tr('本地存储')}</span>}
                  />
                </div>
              </div>
            ) : null}

            {activeCategory === 'appearance' ? (
              <div className="settings-page">
                <h2 className="settings-page-title">{tr('外观')}</h2>

                <div className="settings-scope-banner">
                  <Icon name="info" size={14} />
                  <span>{tr('此处设置全局生效')}</span>
                </div>

                <div className="settings-group-header">{tr('主题与配色')}</div>
                <div className="settings-card">
                  <SettingRow
                    title={tr('外观模式')}
                    description={tr('浅色、深色或跟随系统')}
                    control={
                      <Segmented<ThemeMode>
                        value={s.theme}
                        onChange={(theme) => actions.updateSettings({ theme })}
                        options={[
                          { value: 'light', label: tr('浅色') },
                          { value: 'dark', label: tr('深色') },
                          { value: 'system', label: tr('跟随系统') }
                        ]}
                      />
                    }
                  />
                  <div className="settings-divider" />
                  <SettingRow
                    title={tr('强调色')}
                    description={tr('主按钮、激活态与高亮标记颜色')}
                    control={
                      <div className="swatch-row">
                        {ACCENT_SWATCHES.map((accent) => (
                          <button
                            key={accent}
                            type="button"
                            className={`swatch ${s.accent.toUpperCase() === accent.toUpperCase() ? 'active' : ''}`}
                            style={{ backgroundColor: accent }}
                            title={accent}
                            onClick={() => actions.updateSettings({ accent })}
                          />
                        ))}
                      </div>
                    }
                  />
                  <div className="settings-divider" />
                  <SettingRow
                    title={tr('界面色板')}
                    description={tr('微调工作区背景层次')}
                    control={
                      <Segmented<AppSettings['paletteMode']>
                        value={s.paletteMode}
                        onChange={(paletteMode) => actions.updateSettings({ paletteMode })}
                        options={[
                          { value: 'original', label: tr('原色') },
                          { value: 'preset', label: tr('预设') },
                          { value: 'custom', label: tr('自定义') }
                        ]}
                      />
                    }
                  />
                </div>

                <div className="settings-group-header">{tr('语言与排版')}</div>
                <div className="settings-card">
                  <SettingRow
                    title={tr('界面语言')}
                    control={
                      <Segmented<AppSettings['language']>
                        value={s.language}
                        onChange={(language) => actions.updateSettings({ language })}
                        options={[
                          { value: 'zh-Hans', label: '简体中文' },
                          { value: 'en', label: 'English' }
                        ]}
                      />
                    }
                  />
                  <div className="settings-divider" />
                  <SettingRow
                    title={tr('字体大小')}
                    description={tr('正文与编辑器基础字号 ({0}px)', [s.fontSize])}
                    control={
                      <div className="range-row">
                        <input
                          type="range"
                          min={13}
                          max={20}
                          value={s.fontSize}
                          onChange={(e) => actions.updateSettings({ fontSize: Number(e.target.value) })}
                        />
                        <span className="range-value">{s.fontSize}px</span>
                      </div>
                    }
                  />
                </div>

                <div className="settings-group-header">{tr('界面元素')}</div>
                <div className="settings-card">
                  <SettingRow
                    title={tr('显示功能区')}
                    description={tr('左侧工作台导航与快捷入口')}
                    control={
                      <Toggle
                        checked={s.showRibbon}
                        onChange={(v) => actions.updateSettings({ showRibbon: v })}
                      />
                    }
                  />
                  <div className="settings-divider" />
                  <SettingRow
                    title={tr('显示标签页标题栏')}
                    description={tr('在编辑区顶部显示多文档标签栏')}
                    control={
                      <Toggle
                        checked={s.showTabHeaders}
                        onChange={(v) => actions.updateSettings({ showTabHeaders: v })}
                      />
                    }
                  />
                </div>
              </div>
            ) : null}

            {activeCategory === 'workspace' ? (
              <div className="settings-page">
                <h2 className="settings-page-title">{tr('工作区')}</h2>

                <div className="settings-group-header">{tr('当前工作区')}</div>
                <div className="settings-card">
                  <SettingRow
                    title={activeVault?.name ?? tr('默认工作区')}
                    description={
                      activeVault?.folderUri
                        ? activeVault.folderUri
                        : tr('使用默认应用工作区文件夹')
                    }
                    control={
                      <button
                        type="button"
                        className="settings-btn-inset"
                        onClick={() => void actions.chooseWorkspaceFolder()}
                      >
                        {tr('更换文件夹…')}
                      </button>
                    }
                  />
                  <div className="settings-divider" />
                  <SettingRow
                    title={tr('默认打开方式')}
                    description={tr('点击文件或工作区链接时的打开行为')}
                    control={
                      <Segmented<AppSettings['workspaceDefaultOpenMode']>
                        value={s.workspaceDefaultOpenMode}
                        onChange={(v) => actions.updateSettings({ workspaceDefaultOpenMode: v })}
                        options={[
                          { value: 'current', label: tr('当前窗口标签') },
                          { value: 'new', label: tr('新窗口') }
                        ]}
                      />
                    }
                  />
                </div>
              </div>
            ) : null}

            {activeCategory === 'editor' ? (
              <div className="settings-page">
                <h2 className="settings-page-title">{tr('编辑器')}</h2>

                <div className="settings-group-header">{tr('默认视图与模式')}</div>
                <div className="settings-card">
                  <SettingRow
                    title={tr('新标签默认视图')}
                    control={
                      <Segmented<AppSettings['editorDefaultView']>
                        value={s.editorDefaultView}
                        onChange={(v) => actions.updateSettings({ editorDefaultView: v })}
                        options={[
                          { value: 'live', label: tr('即时预览') },
                          { value: 'source', label: tr('源码模式') },
                          { value: 'reading', label: tr('阅读视图') }
                        ]}
                      />
                    }
                  />
                  <div className="settings-divider" />
                  <SettingRow
                    title={tr('默认编辑模式')}
                    control={
                      <Segmented<'live' | 'source'>
                        value={s.editorDefaultMode}
                        onChange={(v) => actions.updateSettings({ editorDefaultMode: v })}
                        options={[
                          { value: 'live', label: tr('即时预览') },
                          { value: 'source', label: tr('源码模式') }
                        ]}
                      />
                    }
                  />
                </div>

                <div className="settings-group-header">{tr('版面与显示')}</div>
                <div className="settings-card">
                  <SettingRow
                    title={tr('缩减行宽')}
                    description={tr('限制正文最大阅读宽度以提升长文专注度')}
                    control={
                      <Toggle
                        checked={s.editorLimitWidth}
                        onChange={(v) => actions.updateSettings({ editorLimitWidth: v })}
                      />
                    }
                  />
                  <div className="settings-divider" />
                  <SettingRow
                    title={tr('显示内嵌标题')}
                    control={
                      <Toggle
                        checked={s.editorShowTitle}
                        onChange={(v) => actions.updateSettings({ editorShowTitle: v })}
                      />
                    }
                  />
                  <div className="settings-divider" />
                  <SettingRow
                    title={tr('显示编辑状态栏')}
                    control={
                      <Toggle
                        checked={s.editorViewStatus}
                        onChange={(v) => actions.updateSettings({ editorViewStatus: v })}
                      />
                    }
                  />
                </div>
              </div>
            ) : null}

            {activeCategory === 'files' ? (
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
              </div>
            ) : null}

            {activeCategory === 'data' ? (
              <div className="settings-page">
                <h2 className="settings-page-title">{tr('数据与备份')}</h2>

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

                <div className="settings-group-header">{tr('设置与插件合集 (.json)')}</div>
                <div className="settings-card">
                  <SettingRow
                    title={tr('导出设置与插件合集')}
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
                    title={tr('导入设置与插件合集')}
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
                    title={tr('重建工作区索引')}
                    description={tr('从当前工作区文件夹重新扫描笔记、思维导图、白板与双向链接')}
                    control={
                      <button
                        type="button"
                        className="settings-btn-inset"
                        onClick={() => void actions.rebuildIndex()}
                      >
                        {tr('立即重建')}
                      </button>
                    }
                  />
                </div>
              </div>
            ) : null}

            {activeCategory === 'shortcuts' ? (
              <div className="settings-page">
                <h2 className="settings-page-title">{tr('快捷键')}</h2>

                <div className="settings-group-header">{tr('常用快捷键')}</div>
                <div className="settings-card">
                  {SHORTCUTS.map(([keys, label], idx) => (
                    <React.Fragment key={keys}>
                      {idx > 0 ? <div className="settings-divider" /> : null}
                      <div className="setting-row">
                        <div className="setting-copy">
                          <div className="setting-title">{tr(label)}</div>
                        </div>
                        <kbd className="kbd">{keys}</kbd>
                      </div>
                    </React.Fragment>
                  ))}
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
      </div>
    </div>
  );
}

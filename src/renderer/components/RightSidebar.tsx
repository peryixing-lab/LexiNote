import React, { useEffect, useMemo, useRef } from 'react';
import { useStore } from '../store/AppStore';
import { displayTitle, extractOutline } from '../core/markdown';
import { HARNESS_PLUGIN_ID, usePluginHost } from '../plugins/PluginHostController';
import type { PluginRecord } from '../../shared/pluginTypes';
import { Icon } from './Icon';

function iconForPlugin(record: PluginRecord): string {
  const lower = record.id.toLowerCase();
  if (lower.includes('calendar')) return 'sidebar_calendar';
  if (lower.includes('agent')) return 'star';
  return 'sidebar_plugin';
}

export function RightSidebar(): JSX.Element {
  const { state, actions, derived } = useStore();
  const pluginHost = usePluginHost();
  const note = derived.currentNote;
  const { tr } = derived;

  const harnessRecord = useMemo(
    () => pluginHost.records.find((record) => record.id === HARNESS_PLUGIN_ID),
    [pluginHost.records]
  );
  const otherPlugins = useMemo(
    () => pluginHost.records.filter((record) => record.id !== HARNESS_PLUGIN_ID),
    [pluginHost.records]
  );
  const pluginModeId = state.rightSidebarMode.startsWith('plugin:')
    ? state.rightSidebarMode.slice('plugin:'.length)
    : '';
  const selectedPlugin = pluginModeId
    ? pluginHost.records.find((record) => record.id === pluginModeId)
    : undefined;
  const selectedRuntime = pluginModeId ? pluginHost.runtimeInfoById[pluginModeId] : undefined;
  const selectedViews = pluginModeId ? pluginHost.viewsByPlugin[pluginModeId] ?? [] : [];
  const slotRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    const showSurface =
      Boolean(pluginModeId) &&
      Boolean(selectedPlugin) &&
      selectedRuntime?.state !== 'failed' &&
      selectedRuntime?.state !== 'installed-disabled';
    pluginHost.registerSurfaceSlot(pluginModeId, showSurface ? slotRef.current : null);
    return () => {
      pluginHost.registerSurfaceSlot('', null);
    };
  }, [pluginModeId, selectedPlugin, selectedRuntime?.state, pluginHost.registerSurfaceSlot]);

  const selectPlugin = (record: PluginRecord): void => {
    actions.setRightSidebarMode(`plugin:${record.id}`);
    if (!pluginHost.enabledIds.includes(record.id)) {
      void pluginHost.enablePlugin(record.id);
    } else {
      void pluginHost.presentPluginView(record.id, '');
    }
  };

  const headings = useMemo(
    () => (note && !note.id.includes(':') ? extractOutline(note.content) : []),
    [note?.content, note?.id]
  );
  const outgoing = useMemo(
    () => (note ? derived.links.filter((link) => link.sourceId === note.id) : []),
    [derived.links, note?.id]
  );
  const backlinks = useMemo(
    () => (note ? derived.links.filter((link) => link.targetId === note.id) : []),
    [derived.links, note?.id]
  );

  const openTarget = (id: string): void => {
    if (!id) {
      actions.showToast('目标笔记尚未创建');
      return;
    }
    actions.openDocument(id);
  };

  return (
    <aside className="right-sidebar">
      <div className="right-toolbar">
        {harnessRecord ? (
          <button
            type="button"
            className={`right-tab${state.rightSidebarMode === `plugin:${HARNESS_PLUGIN_ID}` ? ' active' : ''}`}
            title={harnessRecord.name || 'Harness'}
            aria-label={harnessRecord.name || 'Harness'}
            onClick={() => selectPlugin(harnessRecord)}
          >
            <Icon name="star" size={18} muted={state.rightSidebarMode !== `plugin:${HARNESS_PLUGIN_ID}`} />
          </button>
        ) : null}
        <button
          type="button"
          className={`right-tab${state.rightSidebarMode === 'outline' ? ' active' : ''}`}
          title={tr('大纲')}
          onClick={() => actions.setRightSidebarMode('outline')}
        >
          <Icon name="sidebar_outline" size={18} muted />
        </button>
        <button
          type="button"
          className={`right-tab${state.rightSidebarMode === 'properties' ? ' active' : ''}`}
          title={tr('笔记属性')}
          onClick={() => actions.setRightSidebarMode('properties')}
        >
          <Icon name="tag" size={18} muted />
        </button>
        {otherPlugins.map((record) => {
          const mode = `plugin:${record.id}`;
          return (
            <button
              key={record.id}
              type="button"
              className={`right-tab${state.rightSidebarMode === mode ? ' active' : ''}`}
              title={record.name || record.id}
              aria-label={record.name || record.id}
              onClick={() => selectPlugin(record)}
            >
              <Icon name={iconForPlugin(record)} size={18} muted={state.rightSidebarMode !== mode} />
            </button>
          );
        })}
        <div className="right-toolbar-spacer" />
        <button
          type="button"
          className="right-tab"
          title={tr('管理插件')}
          onClick={() => actions.openSettings('plugins')}
        >
          <Icon name="sidebar_plugin" size={18} muted />
        </button>
      </div>

      <div className={`right-content${pluginModeId ? ' plugin-mode' : ''}`}>
        {pluginModeId ? (
          !selectedPlugin ? (
            <div className="plugin-pane-state">
              <p className="right-hint">{tr('该插件已卸载或不再可用。')}</p>
              <div className="plugin-pane-actions">
                <button type="button" className="small-btn" onClick={() => actions.openSettings('plugins')}>
                  {tr('管理插件')}
                </button>
                <button type="button" className="small-btn" onClick={() => actions.setRightSidebarMode('outline')}>
                  {tr('返回大纲')}
                </button>
              </div>
            </div>
          ) : selectedRuntime?.state === 'failed' ? (
            <div className="plugin-pane-state">
              <div className="plugin-pane-title">{selectedPlugin.name}</div>
              <div className="plugin-pane-error">{selectedRuntime.lastError || tr('插件加载失败')}</div>
              <div className="plugin-pane-actions">
                <button type="button" className="small-btn" onClick={() => actions.openSettings('plugins')}>
                  {tr('设置插件权限')}
                </button>
                <button
                  type="button"
                  className="primary-btn"
                  onClick={() => void pluginHost.retryPlugin(selectedPlugin.id)}
                >
                  {tr('重试')}
                </button>
              </div>
            </div>
          ) : selectedRuntime?.state === 'installed-disabled' ? (
            <div className="plugin-pane-state">
              <div className="plugin-pane-title">{selectedPlugin.name}</div>
              <p className="right-hint">{tr('插件在当前知识库尚未启用。')}</p>
              <div className="plugin-pane-actions">
                <button
                  type="button"
                  className="primary-btn"
                  onClick={() => void pluginHost.enablePlugin(selectedPlugin.id)}
                >
                  {tr('启用插件')}
                </button>
                <button type="button" className="small-btn" onClick={() => actions.openSettings('plugins')}>
                  {tr('设置插件权限')}
                </button>
              </div>
            </div>
          ) : (
            <div className="plugin-pane-wrap">
              {selectedViews.length > 1 ? (
                <div className="plugin-view-switcher">
                  {selectedViews.map((view) => (
                    <button
                      key={view.id}
                      type="button"
                      className="small-btn"
                      onClick={() => void pluginHost.presentPluginView(selectedPlugin.id, view.id)}
                    >
                      {view.title || view.id}
                    </button>
                  ))}
                </div>
              ) : null}
              <div className="plugin-surface-slot" ref={slotRef}>
                {selectedRuntime?.state === 'starting' ? (
                  <p className="right-hint">{tr('正在启动插件…')}</p>
                ) : null}
              </div>
            </div>
          )
        ) : !note ? (
          <p className="right-hint">{tr('打开一篇笔记以查看大纲。')}</p>
        ) : (
          <>
            <div className="right-title">{displayTitle(note) || tr('未命名笔记')}</div>
            {state.rightSidebarMode === 'properties' ? (
              <div className="right-section">
                <div className="right-section-title">{tr('笔记属性')}</div>
                {note.properties.length === 0 ? (
                  <p className="right-hint">{tr('暂无属性')}</p>
                ) : (
                  note.properties.map((prop) => (
                    <div key={`${prop.key}-${prop.value}`} className="property-row">
                      <span className="property-key">{prop.key}</span>
                      <span className="property-value">{prop.value}</span>
                    </div>
                  ))
                )}
                {note.tags.length > 0 ? (
                  <>
                    <div className="right-section-title spaced">{tr('标签')}</div>
                    <div className="tag-wrap">
                      {note.tags.map((tag) => (
                        <button
                          key={tag}
                          type="button"
                          className="tag-pill"
                          onClick={() => actions.setSearchText(`tag:${tag}`)}
                        >
                          #{tag}
                        </button>
                      ))}
                    </div>
                  </>
                ) : null}
              </div>
            ) : (
              <>
                {headings.length === 0 ? (
                  <p className="right-hint">{tr('用 Markdown 标题梳理思路，大纲会出现在这里。')}</p>
                ) : (
                  <div className="outline-list">
                    {headings.map((heading) => (
                      <button
                        key={`${heading.id}-${heading.title}`}
                        type="button"
                        className={`outline-row level-${Math.min(6, heading.level)}`}
                        style={{ paddingLeft: 8 + (heading.level - 1) * 12 }}
                        onClick={() =>
                          window.dispatchEvent(new CustomEvent('lexi:reveal-line', { detail: { line: heading.lineIndex } }))
                        }
                      >
                        {heading.title}
                      </button>
                    ))}
                  </div>
                )}

                <div className="right-section-title spaced">{tr('出链')} · {outgoing.length}</div>
                {outgoing.length === 0 ? (
                  <p className="right-hint">{tr('在笔记中使用 [[双向链接]]，这里会显示出链。')}</p>
                ) : (
                  outgoing.map((link) => (
                    <button
                      key={`${link.sourceId}-${link.targetTitle}-${link.anchor}`}
                      type="button"
                      className="right-link"
                      onClick={() => openTarget(link.targetId)}
                    >
                      {link.displayText || link.targetTitle}
                    </button>
                  ))
                )}

                <div className="right-section-title spaced">{tr('反向链接')} · {backlinks.length}</div>
                {backlinks.length === 0 ? (
                  <p className="right-hint">{tr('还没有其他笔记链接到这里。')}</p>
                ) : (
                  backlinks.map((link) => (
                    <button
                      key={`${link.sourceId}-${link.targetTitle}-${link.anchor}`}
                      type="button"
                      className="right-link"
                      onClick={() => openTarget(link.sourceId)}
                    >
                      {link.sourceTitle}
                    </button>
                  ))
                )}
              </>
            )}
          </>
        )}
      </div>
    </aside>
  );
}

import React from 'react';
import { useStore } from '../store/AppStore';
import { usePluginHost } from '../plugins/PluginHostController';
import { Icon } from './Icon';
import { GearGlyph, SearchGlyph } from './Symbols';

function ribbonIconName(raw: string): string {
  const lower = (raw || '').toLowerCase();
  if (lower.includes('calendar')) return 'sidebar_calendar';
  if (lower.includes('star') || lower.includes('spark')) return 'star';
  if (lower.includes('graph')) return 'graph';
  if (lower.includes('folder')) return 'folder';
  if (lower.includes('file') || lower.includes('note') || lower.includes('edit')) return 'note';
  if (lower.includes('search')) return 'search';
  if (lower.includes('shield')) return 'shield';
  if (lower.includes('link')) return 'link';
  return 'sidebar_plugin';
}

export function Rail(): JSX.Element {
  const { state, actions, derived } = useStore();
  const pluginHost = usePluginHost();
  const select = (section: 1 | 2 | 4): void => {
    actions.setSection(section);
    actions.setSidebarOpen(true);
  };

  return (
    <nav className="rail" aria-label="功能区">
      {state.settings.showRibbon ? (
        <>
          <button
            type="button"
            className={`ribbon-btn${state.activeSection <= 1 ? ' active' : ''}`}
            title={derived.tr('知识库')}
            onClick={() => select(1)}
          >
            <Icon name="dock_vault" size={19} muted={state.activeSection > 1} />
          </button>
          <button
            type="button"
            className="ribbon-btn"
            title={derived.tr('快速切换文档')}
            onClick={() => actions.openPalette('switcher')}
          >
            <SearchGlyph size={18} color="var(--text-2)" />
          </button>
          <button
            type="button"
            className={`ribbon-btn${state.activeSection === 2 ? ' active' : ''}`}
            title={derived.tr('笔记关联')}
            onClick={() => select(2)}
          >
            <Icon name="graph" size={19} muted={state.activeSection !== 2} />
          </button>
          <button
            type="button"
            className="ribbon-btn"
            title={derived.tr('切换编辑与阅读')}
            onClick={() => void actions.executeCommand('reading')}
          >
            <Icon name="note" size={19} muted />
          </button>
          <button
            type="button"
            className={`ribbon-btn${state.rightSidebarOpen ? ' active' : ''}`}
            title={derived.tr('知识连接')}
            onClick={() => actions.setRightSidebar(!state.rightSidebarOpen, 'outline')}
          >
            <Icon name="link" size={19} muted={!state.rightSidebarOpen} />
          </button>
          {pluginHost.ribbonActions.map((item) => (
            <button
              key={`${item.pluginId}:${item.id}`}
              type="button"
              className="ribbon-btn"
              title={item.title || item.id}
              onClick={() => void pluginHost.triggerRibbon(item.pluginId, item.id)}
            >
              <Icon name={ribbonIconName(item.icon)} size={19} muted />
            </button>
          ))}
        </>
      ) : null}
      <div className="rail-spacer" />
      <button
        type="button"
        className="ribbon-btn"
        title={derived.tr('回收站')}
        onClick={() => actions.setTrashOpen(true)}
      >
        <Icon name="trash" size={19} muted />
      </button>
      <button
        type="button"
        className={`ribbon-btn${state.settingsOpen ? ' active' : ''}`}
        title={derived.tr('设置')}
        onClick={() => actions.openSettings('about')}
      >
        <GearGlyph size={19} color={state.settingsOpen ? 'var(--brand)' : 'var(--text-2)'} />
      </button>
    </nav>
  );
}

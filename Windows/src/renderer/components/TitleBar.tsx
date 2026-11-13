import React, { useEffect, useRef, useState } from 'react';
import { useStore } from '../store/AppStore';
import { Icon } from './Icon';
import { ChevronGlyph, CloseGlyph, GearGlyph, ListGlyph, PanelGlyph, PlusGlyph } from './Symbols';
import { FloatingMenu, MenuEntry } from './FloatingMenu';

function WindowControls(): JSX.Element {
  const [maximized, setMaximized] = useState(false);
  useEffect(() => {
    void window.lexi?.window.isMaximized().then(setMaximized);
    return window.lexi?.window.onMaximized(setMaximized);
  }, []);
  return (
    <div className="window-controls">
      <button type="button" className="window-btn" aria-label="最小化" onClick={() => void window.lexi?.window.minimize()}>
        <svg width="11" height="11" viewBox="0 0 12 12">
          <path d="M2 6h8" stroke="currentColor" strokeWidth="1.1" />
        </svg>
      </button>
      <button
        type="button"
        className="window-btn"
        aria-label={maximized ? '还原' : '最大化'}
        onClick={() => void window.lexi?.window.toggleMaximize().then(setMaximized)}
      >
        {maximized ? (
          <svg width="11" height="11" viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="1">
            <rect x="2" y="3.4" width="6.4" height="6.4" rx="1" />
            <path d="M4 3.4V2.2h5.8v5.8H8.6" />
          </svg>
        ) : (
          <svg width="11" height="11" viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="1">
            <rect x="2.2" y="2.2" width="7.6" height="7.6" rx="1.2" />
          </svg>
        )}
      </button>
      <button type="button" className="window-btn close" aria-label="关闭" onClick={() => void window.lexi?.window.close()}>
        <svg width="11" height="11" viewBox="0 0 12 12">
          <path d="M2.4 2.4l7.2 7.2M9.6 2.4L2.4 9.6" stroke="currentColor" strokeWidth="1.1" />
        </svg>
      </button>
    </div>
  );
}

export function BrandBar(): JSX.Element {
  const { state, derived } = useStore();
  return (
    <div className="brandbar">
      <img className="brand-logo" src={new URL('../assets/brand/lexi_logo.svg', import.meta.url).href} alt="知萤" />
      {state.sidebarOpen ? (
        state.settings.language === 'en' ? (
          <span className="brand-name">LexiNote</span>
        ) : (
          <>
            <span className="brand-name">知萤</span>
            <span className="brand-sub">LexiNote</span>
          </>
        )
      ) : null}
      <span className="brand-spacer" />
    </div>
  );
}

export function TabStrip(): JSX.Element {
  const { state, actions, derived } = useStore();
  const [createMenu, setCreateMenu] = useState<{ x: number; y: number } | null>(null);
  const [tabMenu, setTabMenu] = useState<{ x: number; y: number; id: string } | null>(null);
  const [draggingTab, setDraggingTab] = useState<number | null>(null);
  const tabScrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const active = tabScrollRef.current?.querySelector<HTMLElement>('.tab.active');
    active?.scrollIntoView({ block: 'nearest', inline: 'nearest' });
  }, [state.selectedId, derived.tabs.length]);
  const { tr } = derived;

  const createEntries: MenuEntry[] = [
    { id: 'new-note', label: tr('笔记'), shortcut: 'Ctrl+N', onSelect: () => actions.createNote('markdown') },
    { id: 'new-map', label: tr('思维导图'), onSelect: () => actions.createMap() },
    { id: 'new-canvas', label: tr('白板'), onSelect: () => actions.createCanvas() }
  ];

  const tabEntries: MenuEntry[] = tabMenu
    ? [
        { id: 'close', label: tr('关闭标签页'), shortcut: 'Ctrl+W', onSelect: () => actions.closeTab(tabMenu.id) },
        { id: 'others', label: tr('关闭其他标签页'), onSelect: () => actions.closeOtherTabs() },
        { id: 'all', label: tr('关闭全部标签页'), onSelect: () => actions.closeAllTabs() },
        { separator: true },
        {
          id: 'split',
          label: tr('在右侧分屏打开'),
          onSelect: () => {
            actions.selectTab(tabMenu.id);
            window.setTimeout(() => void actions.executeCommand('split'), 10);
          }
        }
      ]
    : [];

  return (
    <div
      className="tabstrip"
      onDoubleClick={(event) => {
        const target = event.target as HTMLElement;
        if (target.closest('.tab, .new-btn, .panel-btn, .icon-btn, .window-controls, .tab-close')) return;
        void window.lexi?.window.toggleMaximize();
      }}
    >
      <button
        type="button"
        className="icon-btn tabstrip-toggle no-drag"
        title={tr('展开或收起知识库侧栏')}
        onClick={() => actions.setSidebarOpen(!state.sidebarOpen)}
      >
        <ListGlyph size={17} color="var(--text-2)" />
      </button>
      {!state.settings.showRibbon ? (
        <button
          type="button"
          className="icon-btn no-drag"
          title={tr('设置')}
          onClick={() => actions.openSettings('about')}
        >
          <GearGlyph size={18} color="var(--text-2)" />
        </button>
      ) : null}

      <div className="tab-scroll no-drag" ref={tabScrollRef}>
        {derived.tabs.map((tab, tabIndex) => {
          const selected = state.selectedId === tab.id && state.activeSection === 1;
          return (
            <div
              key={tab.id}
              draggable
              className={`tab${selected ? ' active' : ''}${draggingTab === tabIndex ? ' dragging' : ''}`}
              onDragStart={(event) => {
                setDraggingTab(tabIndex);
                event.dataTransfer.effectAllowed = 'move';
                event.dataTransfer.setData('text/plain', String(tabIndex));
              }}
              onDragEnd={() => setDraggingTab(null)}
              onDragOver={(event) => {
                if (draggingTab === null) return;
                event.preventDefault();
                event.dataTransfer.dropEffect = 'move';
              }}
              onDrop={(event) => {
                event.preventDefault();
                const from = Number(event.dataTransfer.getData('text/plain'));
                if (Number.isFinite(from)) actions.moveTab(from, tabIndex);
                setDraggingTab(null);
              }}
              onClick={() => actions.selectTab(tab.id)}
              onAuxClick={(event) => {
                if (event.button === 1) actions.closeTab(tab.id);
              }}
              onContextMenu={(event) => {
                event.preventDefault();
                setTabMenu({ x: event.clientX, y: event.clientY, id: tab.id });
              }}
              title={tab.title}
            >
              <Icon
                name={tab.kind === 'map' ? 'mindmap' : tab.kind === 'canvas' ? 'canvas' : 'note'}
                size={14}
                muted={!selected}
              />
              <span className="tab-title">{tab.title}</span>
              <button
                type="button"
                className="tab-close"
                aria-label={tr('关闭 {0}', [tab.title])}
                onClick={(event) => {
                  event.stopPropagation();
                  actions.closeTab(tab.id);
                }}
              >
                <CloseGlyph size={9} color="var(--text-2)" />
              </button>
            </div>
          );
        })}
      </div>

      <button
        type="button"
        className="new-btn no-drag"
        title={tr('新建内容')}
        onClick={(event) => {
          const rect = (event.currentTarget as HTMLElement).getBoundingClientRect();
          setCreateMenu({ x: rect.right, y: rect.bottom + 6 });
        }}
      >
        <PlusGlyph size={16} color="var(--brand-ink)" />
        <span>{tr('新建')}</span>
        <ChevronGlyph size={9} direction="down" color="var(--brand-ink)" />
      </button>

      <button
        type="button"
        className={`icon-btn panel-btn no-drag${state.rightSidebarOpen ? ' active' : ''}`}
        title={tr(state.rightSidebarOpen ? '收起右侧栏' : '展开右侧栏')}
        onClick={() => actions.setRightSidebar(!state.rightSidebarOpen)}
      >
        <PanelGlyph size={19} color="var(--text-2)" />
      </button>

      <div className="no-drag">
        <WindowControls />
      </div>

      {createMenu ? (
        <FloatingMenu
          x={createMenu.x}
          y={createMenu.y}
          width={168}
          align="right"
          entries={createEntries}
          onClose={() => setCreateMenu(null)}
        />
      ) : null}
      {tabMenu ? (
        <FloatingMenu x={tabMenu.x} y={tabMenu.y} width={196} entries={tabEntries} onClose={() => setTabMenu(null)} />
      ) : null}
    </div>
  );
}

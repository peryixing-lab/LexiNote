import React, { useEffect, useRef, useState } from 'react';
import { useStore } from './store/AppStore';
import { BrandBar, TabStrip } from './components/TitleBar';
import { Rail } from './components/Rail';
import { Sidebar } from './components/Sidebar';
import { Editor } from './components/Editor';
import { RightSidebar } from './components/RightSidebar';
import { GraphView } from './components/GraphView';
import { LibraryView } from './components/LibraryView';
import { MindMapView } from './components/MindMapView';
import { CanvasView } from './components/CanvasView';
import { CommandPalette } from './components/CommandPalette';
import { SettingsDialog } from './components/SettingsDialog';
import { TrashDialog } from './components/TrashDialog';
import { WorkspaceDialog } from './components/WorkspaceDialog';
import { TemplateDialog } from './components/TemplateDialog';
import { HelpDialog } from './components/HelpDialog';
import { WorkspaceOpenDialog } from './components/WorkspaceOpenDialog';
import { Icon } from './components/Icon';
import { usePluginHost } from './plugins/PluginHostController';

function LaunchScreen(): JSX.Element {
  return (
    <div className="launch-screen">
      <img src={new URL('./assets/brand/lexi_logo.svg', import.meta.url).href} alt="知萤" />
      <div className="launch-title">
        知萤 <span>LexiNote</span>
      </div>
      <div className="launch-sub">想记就记，需要时足够专业。</div>
      <div className="launch-bar">
        <span />
      </div>
    </div>
  );
}

function Workspace(): JSX.Element {
  const { state, actions, derived } = useStore();
  const selected = state.selectedId;
  const groupOpen = state.groupTabs.length > 0 && state.activeSection <= 1;

  let content: React.ReactNode;
  if (!state.activeSection || state.activeSection === 1) {
    if (!selected) {
      content = (
        <div className="editor-empty">
          <Icon name="note" size={32} />
          <h2>{derived.tr('选择或新建一篇笔记')}</h2>
          <p>{derived.tr('从左侧打开已有笔记，或点击右上角“新建”开始记录。')}</p>
          <div className="empty-actions">
            <button type="button" className="primary-btn" onClick={() => actions.createNote('markdown')}>
              {derived.tr('新建笔记')}
            </button>
            <button type="button" className="small-btn" onClick={() => actions.setTemplatesOpen(true)}>
              {derived.tr('从模板新建')}
            </button>
          </div>
        </div>
      );
    } else if (selected.startsWith('map:')) {
      content = <MindMapView />;
    } else if (selected.startsWith('canvas:')) {
      content = <CanvasView />;
    } else {
      content = <Editor />;
    }
  } else if (state.activeSection === 2) {
    content = <GraphView />;
  } else {
    content = <LibraryView />;
  }

  return (
    <div className="workspace-content">
      <div className="workspace-doc">{content}</div>
      {groupOpen ? (
        <div className="group-pane">
          <div className="group-head">
            <span>{derived.tr('标签组')}</span>
            <button type="button" className="small-btn ghost" onClick={() => void actions.executeCommand('close-split')}>
              {derived.tr('关闭分组')}
            </button>
          </div>
          <div className="group-body">
            {selected.startsWith('map:') ? <MindMapView /> : selected.startsWith('canvas:') ? <CanvasView /> : <Editor />}
          </div>
        </div>
      ) : null}
    </div>
  );
}

export function App(): JSX.Element {
  const { state, actions, derived } = useStore();
  const pluginHost = usePluginHost();
  const [resizing, setResizing] = useState<'left' | 'right' | null>(null);
  const [dragFiles, setDragFiles] = useState(false);
  const resizeRef = useRef<{ startX: number; startWidth: number; kind: 'left' | 'right' } | null>(null);

  const leftWidth = (state.settings.showRibbon ? 56 : 0) + (state.sidebarOpen ? state.settings.sidebarWidth : 0);
  const rightWidth = state.rightSidebarOpen ? state.settings.rightSidebarWidth : 0;

  useEffect(() => {
    const onMove = (event: PointerEvent): void => {
      const current = resizeRef.current;
      if (!current) return;
      const dx = event.clientX - current.startX;
      if (current.kind === 'left') {
        const next = Math.max(200, Math.min(420, current.startWidth + dx));
        actions.updateSettings({ sidebarWidth: next });
      } else {
        const next = Math.max(220, Math.min(520, current.startWidth - dx));
        actions.updateSettings({ rightSidebarWidth: next });
      }
    };
    const onUp = (): void => {
      resizeRef.current = null;
      setResizing(null);
    };
    window.addEventListener('pointermove', onMove);
    window.addEventListener('pointerup', onUp);
    return () => {
      window.removeEventListener('pointermove', onMove);
      window.removeEventListener('pointerup', onUp);
    };
  }, [actions]);

  useEffect(() => {
    const base = state.settings.language === 'en' ? 'LexiNote' : '知萤 LexiNote';
    const vault = derived.activeVault?.name;
    document.title = vault ? `${base} — ${vault}` : base;
  }, [state.settings.language, derived.activeVault?.name]);

  useEffect(() => {
    const dispose = window.lexi?.window.onFlushRequest(() => {
      void actions.saveNow().finally(() => window.lexi?.window.flushDone());
    });
    return () => dispose?.();
  }, [actions]);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent): void => {
      if (event.key === 'F1') {
        event.preventDefault();
        actions.setHelpOpen(true);
      }
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [actions]);

  // Screenshot automation used by scripts/screenshot.mjs; harmless in normal use.
  useEffect(() => {
    window.__lexiShot = (name: string): void => {
      actions.closePalette();
      actions.closeSettings();
      actions.setTrashOpen(false);
      actions.setWorkspacesOpen(false);
      actions.setTemplatesOpen(false);
      actions.setHelpOpen(false);
      actions.cancelWorkspaceOpen();
      actions.setRightSidebar(false);
      actions.setSidebarOpen(true);
      if (name !== 'dark' && name !== 'appearance-dark') {
        actions.updateSettings({ theme: 'light' });
      }
      if (!name.startsWith('english')) {
        actions.updateSettings({ language: 'zh-Hans' });
      }
      if (name === 'right') {
        actions.setSection(1);
        actions.setRightSidebar(true);
      }
      if (name === 'reading' || name === 'source') {
        const id = state.notes.find((note) => note.id === state.selectedId)?.id ?? state.notes[0]?.id;
        if (id) {
          actions.setSection(1);
          actions.openDocument(id);
          actions.setEditorMode(id, name === 'reading' ? 'reading' : 'source');
        }
        return;
      }
      if (name.startsWith('note:')) {
        actions.setSection(1);
        actions.openDocument(name.substring(5));
        return;
      }
      switch (name) {
        case 'workspace':
          actions.setSection(1);
          break;
        case 'right':
          actions.setSection(1);
          break;
        case 'palette':
          actions.openPalette('commands');
          break;
        case 'switcher':
          actions.openPalette('switcher');
          break;
        case 'settings':
          actions.openSettings('about');
          break;
        case 'appearance':
          actions.openSettings('appearance');
          break;
        case 'interface':
          actions.openSettings('interface');
          break;
        case 'data':
          actions.openSettings('data');
          break;
        case 'graph':
          actions.setSection(2);
          break;
        case 'library':
          actions.setSection(4);
          break;
        case 'mindmap': {
          const map = state.maps.find((item) => item.vaultId === state.activeVaultId);
          if (map) {
            actions.setSection(1);
            actions.openDocument(`map:${map.id}`);
          }
          break;
        }
        case 'canvas': {
          const board = state.canvases.find((item) => item.vaultId === state.activeVaultId);
          if (board) {
            actions.setSection(1);
            actions.openDocument(`canvas:${board.id}`);
          }
          break;
        }
        case 'trash':
          actions.setTrashOpen(true);
          break;
        case 'workspaces':
          actions.setWorkspacesOpen(true);
          break;
        case 'workspace-open': {
          const other = state.vaults.find((vault) => vault.id !== state.activeVaultId);
          if (other) actions.requestWorkspace(other.id);
          break;
        }
        case 'workspace-modes':
          actions.openSettings('editor');
          break;
        case 'templates':
          actions.setTemplatesOpen(true);
          break;
        case 'help':
          actions.setHelpOpen(true);
          break;
        case 'dark':
          actions.updateSettings({ theme: 'dark' });
          actions.setSection(1);
          break;
        case 'appearance-dark':
          actions.updateSettings({ theme: 'dark' });
          actions.openSettings('appearance');
          break;
        case 'english':
          actions.updateSettings({ language: 'en', theme: 'light' });
          actions.setSection(1);
          break;
        case 'english-settings':
          actions.updateSettings({ language: 'en', theme: 'light' });
          actions.openSettings('appearance');
          break;
        case 'english-library':
          actions.updateSettings({ language: 'en', theme: 'light' });
          actions.setSection(4);
          break;
        default:
          break;
      }
    };
  }, [actions, state.maps, state.canvases, state.activeVaultId]);

  if (!state.ready) return <LaunchScreen />;

  const onDropFiles = async (event: React.DragEvent): Promise<void> => {
    event.preventDefault();
    setDragFiles(false);
    const files = Array.from(event.dataTransfer.files).filter((file) =>
      /\.(md|markdown|txt)$/i.test(file.name)
    );
    if (files.length === 0) {
      actions.showToast('请拖入 Markdown（.md / .markdown / .txt）文件');
      return;
    }
    let imported = 0;
    for (const file of files) {
      const content = await file.text();
      const title = file.name.replace(/\.(md|markdown|txt)$/i, '');
      const id = actions.createNote('markdown', title);
      actions.updateNote(id, { content, notebook: '外部导入' });
      imported += 1;
    }
    actions.showToast(`已导入 ${imported} 篇笔记`);
  };

  return (
    <div
      className={`app${resizing ? ' resizing' : ''}`}
      onDragOver={(event) => {
        if (event.dataTransfer.types.includes('Files')) {
          event.preventDefault();
          setDragFiles(true);
        }
      }}
      onDragLeave={(event) => {
        if (!event.currentTarget.contains(event.relatedTarget as Node)) setDragFiles(false);
      }}
      onDrop={(event) => void onDropFiles(event)}
    >
      <div className="app-left" style={{ width: leftWidth }}>
        <BrandBar />
        <div className="left-body">
          {state.settings.showRibbon ? <Rail /> : null}
          {state.sidebarOpen ? <Sidebar /> : null}
        </div>
      </div>

      {state.sidebarOpen ? (
        <div
          className={`resize-handle left${resizing === 'left' ? ' active' : ''}`}
          role="separator"
          aria-orientation="vertical"
          aria-label={derived.tr('拖动调整知识库侧栏宽度')}
          onPointerDown={(event) => {
            resizeRef.current = { startX: event.clientX, startWidth: state.settings.sidebarWidth, kind: 'left' };
            setResizing('left');
          }}
        />
      ) : null}

      <div className="app-main">
        <TabStrip />
        <div className="main-body">
          <Workspace />
          {state.rightSidebarOpen ? (
            <div
              className={`resize-handle right${resizing === 'right' ? ' active' : ''}`}
              role="separator"
              aria-orientation="vertical"
              aria-label={derived.tr('拖动调整右侧栏宽度')}
              onPointerDown={(event) => {
                resizeRef.current = { startX: event.clientX, startWidth: state.settings.rightSidebarWidth, kind: 'right' };
                setResizing('right');
              }}
            />
          ) : null}
          <div className="right-slot" style={{ width: rightWidth }}>
            {state.rightSidebarOpen ? <RightSidebar /> : null}
          </div>
        </div>
      </div>

      {state.paletteOpen ? <CommandPalette /> : null}
      {state.settingsOpen ? <SettingsDialog /> : null}
      {state.trashOpen ? <TrashDialog /> : null}
      {state.workspacesOpen ? <WorkspaceDialog /> : null}
      {state.workspacePrompt ? <WorkspaceOpenDialog /> : null}
      {state.templatesOpen ? <TemplateDialog /> : null}
      {state.helpOpen ? <HelpDialog /> : null}

      {dragFiles ? (
        <div className="drop-overlay">
          <div className="drop-card">
            <Icon name="export" size={26} />
            <strong>松开以导入 Markdown</strong>
            <span>支持 .md / .markdown / .txt，导入到「外部导入」文件夹</span>
          </div>
        </div>
      ) : null}

      {state.toast ? (
        <div className="toast" key={state.toast.id}>
          {state.toast.text}
        </div>
      ) : null}

      {pluginHost.notices.length > 0 ? (
        <div className="plugin-notices" aria-live="polite">
          {pluginHost.notices.map((notice) => {
            const pluginName =
              pluginHost.records.find((record) => record.id === notice.pluginId)?.name || notice.pluginId;
            return (
              <div className="plugin-notice-toast" key={notice.id}>
                <div className="plugin-notice-body">
                  <span className="plugin-notice-source">{pluginName}</span>
                  <span>{notice.message}</span>
                </div>
                <button
                  type="button"
                  className="plugin-notice-close"
                  aria-label={derived.tr('关闭通知')}
                  onClick={() => pluginHost.dismissNotice(notice.id)}
                >
                  ×
                </button>
              </div>
            );
          })}
        </div>
      ) : null}

      {pluginHost.confirmRequest ? (
        <div className="modal-backdrop plugin-confirm-backdrop" role="presentation">
          <div className="dialog-card plugin-confirm-card" role="dialog" aria-modal="true">
            <div className="dialog-head">
              <h3>{pluginHost.confirmRequest.title}</h3>
            </div>
            <div className="plugin-confirm-meta">
              {derived.tr('来自插件：{0}', [
                pluginHost.records.find((record) => record.id === pluginHost.confirmRequest?.pluginId)?.name ||
                  pluginHost.confirmRequest.pluginId
              ])}
            </div>
            {pluginHost.confirmRequest.body ? (
              <p className="plugin-confirm-body">{pluginHost.confirmRequest.body}</p>
            ) : null}
            <div className="plugin-confirm-actions">
              <button
                type="button"
                className="small-btn"
                onClick={() => pluginHost.resolveConfirm(false)}
              >
                {derived.tr('取消')}
              </button>
              <button
                type="button"
                className="primary-btn"
                onClick={() => pluginHost.resolveConfirm(true)}
              >
                {derived.tr('确认')}
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
}

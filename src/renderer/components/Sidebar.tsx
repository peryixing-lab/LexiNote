import React, { useMemo, useRef, useState } from 'react';
import { useStore } from '../store/AppStore';
import type { NoteItem } from '../../shared/types';
import { displayTitle, extractSnippet } from '../core/markdown';
import { Icon } from './Icon';
import { ChevronGlyph, CloseGlyph, SearchGlyph } from './Symbols';
import { FloatingMenu, MenuEntry } from './FloatingMenu';

export function Sidebar(): JSX.Element {
  const { state, actions, derived } = useStore();
  const [noteMenu, setNoteMenu] = useState<{ x: number; y: number; note: NoteItem } | null>(null);
  const [vaultMenu, setVaultMenu] = useState<{ x: number; y: number } | null>(null);
  const searchRef = useRef<HTMLInputElement>(null);
  const { tr } = derived;

  const folderNotes = useMemo(() => {
    const map = new Map<string, NoteItem[]>();
    for (const note of derived.visibleNotes) {
      if (!state.activeProjectId && !state.searchText && note.projectId) continue;
      const name = note.notebook || tr('未分类');
      const list = map.get(name) ?? [];
      list.push(note);
      map.set(name, list);
    }
    return map;
  }, [derived.visibleNotes, state.activeProjectId, state.searchText, tr]);

  const projectRows = !state.activeProjectId && !state.searchText;
  const maps = state.maps.filter(
    (map) => map.trashedAt === 0 && map.vaultId === state.activeVaultId && (!state.activeProjectId || map.projectId === state.activeProjectId)
  );
  const canvases = state.canvases.filter(
    (board) => board.vaultId === state.activeVaultId && (!state.activeProjectId || board.projectId === state.activeProjectId)
  );

  const openNoteMenu = (event: React.MouseEvent, note: NoteItem): void => {
    event.preventDefault();
    event.stopPropagation();
    setNoteMenu({ x: event.clientX, y: event.clientY, note });
  };

  const noteEntries: MenuEntry[] = noteMenu
    ? [
        {
          id: 'open',
          label: tr('打开'),
          onSelect: () => actions.openDocument(noteMenu.note.id)
        },
        {
          id: 'fav',
          label: noteMenu.note.favorite ? tr('取消收藏') : tr('收藏'),
          checked: noteMenu.note.favorite,
          onSelect: () => actions.toggleFavorite(noteMenu.note.id)
        },
        {
          id: 'pin',
          label: noteMenu.note.pinned ? tr('取消置顶') : tr('置顶'),
          checked: noteMenu.note.pinned,
          onSelect: () => actions.togglePin(noteMenu.note.id)
        },
        { separator: true },
        {
          id: 'rename',
          label: tr('重命名'),
          onSelect: () => {
            actions.openDocument(noteMenu.note.id);
            window.setTimeout(() => window.dispatchEvent(new CustomEvent('lexi:rename-title')), 80);
          }
        },
        {
          id: 'duplicate',
          label: tr('创建副本'),
          onSelect: () => actions.duplicateNote(noteMenu.note.id)
        },
        { separator: true },
        {
          id: 'trash',
          label: tr('移到回收站'),
          danger: true,
          onSelect: () => actions.trashNote(noteMenu.note.id)
        }
      ]
    : [];

  const vaultEntries: MenuEntry[] = [
    { header: tr('选择工作区') },
    ...state.vaults.map<MenuEntry>((vault) => ({
      id: vault.id,
      label: vault.id === state.activeVaultId ? tr('{0} · 当前', [vault.name]) : vault.name,
      checked: vault.id === state.activeVaultId,
      disabled: vault.id === state.activeVaultId,
      onSelect: () => actions.requestWorkspace(vault.id)
    })),
    { separator: true },
    { header: tr('当前工作区的项目') },
    {
      id: 'all-projects',
      label: state.activeProjectId ? tr('全部项目') : tr('全部项目 · 当前'),
      checked: !state.activeProjectId,
      onSelect: () => actions.setActiveProject('')
    },
    ...state.projects
      .filter((project) => project.vaultId === state.activeVaultId)
      .map<MenuEntry>((project) => ({
        id: project.id,
        label: project.id === state.activeProjectId ? tr('{0} · 当前', [project.name]) : project.name,
        checked: project.id === state.activeProjectId,
        onSelect: () => actions.setActiveProject(project.id)
      })),
    { separator: true },
    {
      id: 'manage',
      label: tr('工作区与项目…'),
      onSelect: () => actions.setWorkspacesOpen(true)
    },
    {
      id: 'library',
      label: tr('文档管理'),
      onSelect: () => actions.setSection(4)
    }
  ];

  return (
    <aside className="sidebar">
      <div className="sidebar-head">
        <span>{tr('知识库')}</span>
        <span className="sidebar-count">{derived.visibleNotes.length}</span>
      </div>

      <div className="sidebar-search">
        <SearchGlyph size={15} color="var(--text-2)" />
        <input
          ref={searchRef}
          value={state.searchText}
          placeholder={tr('搜索 · tag: type: notebook:')}
          onChange={(event) => actions.setSearchText(event.target.value)}
          aria-label={tr('搜索笔记')}
        />
        {state.searchText ? (
          <button type="button" className="search-clear" aria-label={tr('清空搜索')} onClick={() => actions.setSearchText('')}>
            <CloseGlyph size={9} color="var(--text-2)" />
          </button>
        ) : null}
      </div>

      <div className="sidebar-quick">
        <button type="button" className="ghost-btn" onClick={() => void actions.executeCommand('daily')}>
          {tr('今日笔记')}
        </button>
        <button type="button" className="ghost-btn" onClick={() => actions.setTemplatesOpen(true)}>
          {tr('模板')}
        </button>
      </div>

      <div className="sidebar-filters">
        <button
          type="button"
          className={`chip${state.favoritesOnly ? '' : ' active'}`}
          onClick={() => actions.setFavoritesOnly(false)}
        >
          {tr('全部笔记')}
        </button>
        <button
          type="button"
          className={`chip${state.favoritesOnly ? ' active' : ''}`}
          onClick={() => actions.setFavoritesOnly(true)}
        >
          {tr('收藏')}
        </button>
      </div>

      <div className="sidebar-scroll">
        {projectRows
          ? state.projects
              .filter((project) => project.vaultId === state.activeVaultId)
              .map((project) => (
                <button
                  key={project.id}
                  type="button"
                  className="project-row"
                  onClick={() => actions.setActiveProject(project.id)}
                >
                  <Icon name="folder" size={16} />
                  <span className="project-name">{project.name}</span>
                  {project.favorite ? <Icon name="star" size={12} /> : null}
                  <ChevronGlyph size={11} color="var(--text-2)" />
                </button>
              ))
          : null}

        {[...folderNotes.entries()].map(([folder, notes]) => {
          const closed = state.closedFolders.includes(folder) && !state.searchText;
          return (
            <div className="folder-group" key={folder}>
              <button type="button" className="folder-row" onClick={() => actions.toggleFolder(folder)}>
                <ChevronGlyph size={9} direction={closed ? 'right' : 'down'} color="var(--text-2)" />
                <Icon name="folder" size={15} muted />
                <span className="folder-name">{folder}</span>
                <span className="folder-count">{notes.length}</span>
              </button>
              {!closed
                ? notes.map((note) => (
                    <button
                      key={note.id}
                      type="button"
                      className={`note-row${state.selectedId === note.id && state.activeSection <= 1 ? ' active' : ''}`}
                      onClick={() => actions.openDocument(note.id)}
                      onContextMenu={(event) => openNoteMenu(event, note)}
                      title={extractSnippet(note)}
                    >
                      <Icon name={note.noteType === 'study' ? 'study' : 'note'} size={15} muted={state.selectedId !== note.id} />
                      <span className="note-title">{displayTitle(note)}</span>
                      {note.favorite ? <Icon name="star" size={11} /> : null}
                    </button>
                  ))
                : null}
            </div>
          );
        })}

        {derived.visibleNotes.length === 0 ? (
          <div className="sidebar-empty">
            <span>
              {state.searchText
                ? tr('没有找到匹配的笔记')
                : state.favoritesOnly
                  ? tr('收藏的笔记会出现在这里')
                  : tr('写下第一条笔记')}
            </span>
            {!state.searchText && !state.favoritesOnly ? (
              <button type="button" className="small-btn" onClick={() => actions.createNote('markdown')}>
                {tr('新建笔记')}
              </button>
            ) : null}
          </div>
        ) : null}

        {!state.searchText && !state.favoritesOnly && (maps.length > 0 || canvases.length > 0) ? (
          <>
            <div className="sidebar-divider" />
            <div className="sidebar-section-title">{tr('可视化空间')}</div>
            {maps.map((map) => (
              <button
                key={map.id}
                type="button"
                className={`space-row${state.selectedId === `map:${map.id}` && state.activeSection <= 1 ? ' active' : ''}`}
                onClick={() => actions.openDocument(`map:${map.id}`)}
              >
                <Icon name="mindmap" size={15} muted={state.selectedId !== `map:${map.id}`} />
                <span>{map.title || tr('未命名导图')}</span>
              </button>
            ))}
            {canvases.map((board) => (
              <button
                key={board.id}
                type="button"
                className={`space-row${state.selectedId === `canvas:${board.id}` && state.activeSection <= 1 ? ' active' : ''}`}
                onClick={() => actions.openDocument(`canvas:${board.id}`)}
              >
                <Icon name="canvas" size={15} />
                <span>{board.title || tr('未命名白板')}</span>
              </button>
            ))}
          </>
        ) : null}
      </div>

      <button
        type="button"
        className="vault-switcher"
        onClick={(event) => {
          const rect = (event.currentTarget as HTMLElement).getBoundingClientRect();
          setVaultMenu({ x: rect.left, y: rect.top - 8 });
        }}
      >
        <Icon name="folder" size={17} />
        <span className="vault-text">
          <span className="vault-name">{derived.activeVault?.name ?? tr('工作区')}</span>
          <span className="vault-project">{derived.activeProject?.name ?? tr('全部项目')}</span>
        </span>
        <ChevronGlyph size={10} color="var(--text-2)" />
      </button>

      {noteMenu ? (
        <FloatingMenu x={noteMenu.x} y={noteMenu.y} width={200} entries={noteEntries} onClose={() => setNoteMenu(null)} />
      ) : null}
      {vaultMenu ? (
        <FloatingMenu
          x={vaultMenu.x}
          y={vaultMenu.y}
          width={250}
          align="left"
          entries={vaultEntries}
          onClose={() => setVaultMenu(null)}
        />
      ) : null}
    </aside>
  );
}

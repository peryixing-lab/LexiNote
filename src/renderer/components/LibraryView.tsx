import React, { useMemo, useState } from 'react';
import { useStore } from '../store/AppStore';
import type { NoteSortMode } from '../../shared/types';
import { displayTitle, extractSnippet, isNoteUnconnected } from '../core/markdown';
import { formatDateTime } from '../core/i18n';
import { matchesSearch, sortNotes } from '../core/search';
import { HighlightText } from './HighlightText';
import { Icon } from './Icon';
import { CloseGlyph, SearchGlyph } from './Symbols';

export function LibraryView(): JSX.Element {
  const { state, actions, derived } = useStore();
  const { tr } = derived;
  const [query, setQuery] = useState('');
  const [tagFilter, setTagFilter] = useState('');
  const [unconnectedOnly, setUnconnectedOnly] = useState(false);
  const sort: NoteSortMode = state.settings.librarySort ?? 'updated';
  const [view, setView] = useState<'grid' | 'list'>('grid');

  const notes = useMemo(() => {
    const list = derived.hydratedNotes.filter(
      (note) =>
        note.vaultId === state.activeVaultId &&
        note.trashedAt === 0 &&
        (!state.activeProjectId || note.projectId === state.activeProjectId) &&
        matchesSearch(note, query) &&
        (!tagFilter || note.tags.includes(tagFilter)) &&
        (!unconnectedOnly || isNoteUnconnected(note.id, derived.links))
    );
    return sortNotes(list, sort, { pinnedFirst: true });
  }, [
    derived.hydratedNotes,
    derived.links,
    state.activeVaultId,
    state.activeProjectId,
    query,
    tagFilter,
    unconnectedOnly,
    sort
  ]);

  const tags = useMemo(() => {
    const counter = new Map<string, number>();
    for (const note of state.notes) {
      if (note.vaultId !== state.activeVaultId || note.trashedAt > 0) continue;
      for (const tag of note.tags) counter.set(tag, (counter.get(tag) || 0) + 1);
    }
    return [...counter.entries()].sort((a, b) => b[1] - a[1]).slice(0, 18);
  }, [state.notes, state.activeVaultId]);

  return (
    <div className="library-view">
      <div className="aux-header library-head">
        <div>
          <h1>{tr('文档管理')}</h1>
          <p>
            {derived.activeVault?.name ?? tr('工作区')} · {notes.length} {tr('篇笔记')} ·{' '}
            {state.maps.filter((map) => map.vaultId === state.activeVaultId && map.trashedAt === 0).length}{' '}
            {tr('个导图')}
          </p>
        </div>
        <div className="library-tools">
          <div className="library-search">
            <SearchGlyph size={14} color="var(--text-2)" />
            <input
              value={query}
              placeholder={tr('搜索标题、正文、标签…')}
              onChange={(event) => setQuery(event.target.value)}
              aria-label={tr('搜索文档')}
            />
            {query ? (
              <button type="button" className="search-clear" onClick={() => setQuery('')} aria-label={tr('清空搜索')}>
                <CloseGlyph size={9} color="var(--text-2)" />
              </button>
            ) : null}
          </div>
          <select
            className="select compact"
            value={sort}
            onChange={(event) => actions.setLibrarySort(event.target.value as NoteSortMode)}
            aria-label={tr('排序')}
          >
            <option value="updated">{tr('最近更新')}</option>
            <option value="accessed">{tr('最近访问')}</option>
            <option value="created">{tr('最近创建')}</option>
            <option value="title">{tr('按标题')}</option>
          </select>
          <div className="segmented compact">
            <button type="button" className={view === 'grid' ? 'active' : ''} onClick={() => setView('grid')}>
              {tr('卡片')}
            </button>
            <button type="button" className={view === 'list' ? 'active' : ''} onClick={() => setView('list')}>
              {tr('列表')}
            </button>
          </div>
          <button type="button" className="primary-btn" onClick={() => actions.createNote('markdown')}>
            {tr('新建')}
          </button>
        </div>
      </div>

      <div className="library-tags">
        <button
          type="button"
          className={`tag-chip${!tagFilter && !unconnectedOnly ? ' active' : ''}`}
          onClick={() => {
            setTagFilter('');
            setUnconnectedOnly(false);
          }}
        >
          {tr('全部')}
        </button>
        <button
          type="button"
          className={`tag-chip${unconnectedOnly ? ' active' : ''}`}
          onClick={() => setUnconnectedOnly((v) => !v)}
        >
          {tr('未连接')} <small>{derived.unconnectedNotes.length}</small>
        </button>
        {tags.map(([tag, count]) => (
          <button
            key={tag}
            type="button"
            className={`tag-chip${tagFilter === tag ? ' active' : ''}`}
            onClick={() => setTagFilter(tagFilter === tag ? '' : tag)}
          >
            #{tag} <small>{count}</small>
          </button>
        ))}
      </div>

      <div className={`library-scroll ${view}`}>
        {notes.length === 0 ? (
          <div className="library-empty">
            <Icon name="note" size={30} />
            <p>{tr('没有找到匹配的笔记')}</p>
            <span>{tr('试试清空搜索，或新建一篇笔记。')}</span>
          </div>
        ) : view === 'grid' ? (
          <div className="note-grid">
            {notes.map((note) => (
              <article
                key={note.id}
                className={`note-card${state.selectedId === note.id ? ' active' : ''}`}
                onClick={() => actions.openDocument(note.id)}
              >
                <header>
                  <Icon name={note.noteType === 'study' ? 'study' : 'note'} size={16} muted />
                  <span className="note-card-notebook">{note.notebook}</span>
                  {isNoteUnconnected(note.id, derived.links) ? (
                    <span className="unconnected-pill">{tr('未连接')}</span>
                  ) : null}
                  <span className="note-card-spacer" />
                  <button
                    type="button"
                    className={`card-action${note.favorite ? ' on' : ''}`}
                    title={tr('收藏')}
                    onClick={(event) => {
                      event.stopPropagation();
                      actions.toggleFavorite(note.id);
                    }}
                  >
                    <Icon name="star" size={13} muted={!note.favorite} />
                  </button>
                  <button
                    type="button"
                    className={`card-action${note.pinned ? ' on' : ''}`}
                    title={tr('置顶')}
                    onClick={(event) => {
                      event.stopPropagation();
                      actions.togglePin(note.id);
                    }}
                  >
                    <Icon name="pin" size={13} muted={!note.pinned} />
                  </button>
                </header>
                <h3>
                  <HighlightText text={displayTitle(note)} query={query} />
                </h3>
                <p>
                  <HighlightText text={extractSnippet(note, query)} query={query} />
                </p>
                <footer>
                  <span>
                    {sort === 'accessed' && note.lastOpenedAt && note.lastOpenedAt > 0
                      ? tr('访问 {0}', [formatDateTime(note.lastOpenedAt, state.settings.language)])
                      : formatDateTime(note.updatedAt, state.settings.language)}
                  </span>
                  <span>{note.tags.slice(0, 2).map((tag) => `#${tag}`).join(' ')}</span>
                </footer>
              </article>
            ))}
          </div>
        ) : (
          <div className="note-list">
            <div className="note-list-head">
              <span>{tr('标题')}</span>
              <span>{tr('文件夹')}</span>
              <span>{tr('标签')}</span>
              <span>{sort === 'accessed' ? tr('最近访问') : tr('更新时间')}</span>
              <span />
            </div>
            {notes.map((note) => (
              <button
                key={note.id}
                type="button"
                className={`note-list-row${state.selectedId === note.id ? ' active' : ''}`}
                onClick={() => actions.openDocument(note.id)}
              >
                <span className="list-title">
                  <Icon name={note.noteType === 'study' ? 'study' : 'note'} size={15} muted />
                  <HighlightText text={displayTitle(note)} query={query} />
                  {isNoteUnconnected(note.id, derived.links) ? (
                    <span className="unconnected-pill">{tr('未连接')}</span>
                  ) : null}
                  {note.favorite ? <Icon name="star" size={11} /> : null}
                </span>
                <span>{note.notebook}</span>
                <span className="list-tags">{note.tags.slice(0, 2).map((tag) => `#${tag}`).join(' ') || '—'}</span>
                <span>
                  {formatDateTime(
                    sort === 'accessed' && note.lastOpenedAt && note.lastOpenedAt > 0 ? note.lastOpenedAt : note.updatedAt,
                    state.settings.language
                  )}
                </span>
                <span
                  className="list-trash"
                  role="button"
                  tabIndex={0}
                  title={tr('移到回收站')}
                  onClick={(event) => {
                    event.stopPropagation();
                    actions.trashNote(note.id);
                  }}
                  onKeyDown={(event) => {
                    if (event.key === 'Enter') actions.trashNote(note.id);
                  }}
                >
                  <Icon name="trash" size={14} muted />
                </span>
              </button>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

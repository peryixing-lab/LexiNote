import React, { useState } from 'react';
import { useStore } from '../store/AppStore';
import { displayTitle } from '../core/markdown';
import { formatDateTime } from '../core/i18n';
import { Icon } from './Icon';
import { CloseGlyph, RestoreGlyph } from './Symbols';

export function TrashDialog(): JSX.Element {
  const { state, actions, derived } = useStore();
  const { tr } = derived;
  const [confirmEmpty, setConfirmEmpty] = useState(false);

  return (
    <div className="overlay dialog-overlay" onPointerDown={(event) => {
      if (event.target === event.currentTarget) actions.setTrashOpen(false);
    }}>
      <div className="dialog trash-dialog" role="dialog" aria-modal="true" aria-label={tr('回收站')}>
        <div className="dialog-head">
          <div>
            <h2>{tr('回收站')}</h2>
            <p>{tr('已删除的笔记和导图会保留在这里，直到你永久删除。')}</p>
          </div>
          <button type="button" className="icon-btn tiny" aria-label={tr('关闭')} onClick={() => actions.setTrashOpen(false)}>
            <CloseGlyph size={12} color="var(--text-2)" />
          </button>
        </div>

        <div className="dialog-body">
          {derived.trashNotes.length === 0 && derived.trashMaps.length === 0 ? (
            <div className="trash-empty">
              <Icon name="trash" size={30} />
              <p>{tr('回收站是空的')}</p>
            </div>
          ) : null}

          {derived.trashNotes.map((note) => (
            <div className="trash-row" key={note.id}>
              <Icon name={note.noteType === 'study' ? 'study' : 'note'} size={16} muted />
              <div className="trash-text">
                <span className="trash-title">{displayTitle(note)}</span>
                <span className="trash-meta">
                  {note.notebook} · {formatDateTime(note.trashedAt, state.settings.language)}
                </span>
              </div>
              <button type="button" className="small-btn" onClick={() => actions.restoreNote(note.id)}>
                <RestoreGlyph size={13} /> {tr('恢复')}
              </button>
              <button type="button" className="small-btn danger" onClick={() => actions.deleteForever(note.id)}>
                {tr('永久删除')}
              </button>
            </div>
          ))}

          {derived.trashMaps.map((map) => (
            <div className="trash-row" key={map.id}>
              <Icon name="mindmap" size={16} muted />
              <div className="trash-text">
                <span className="trash-title">{map.title || tr('未命名导图')}</span>
                <span className="trash-meta">
                  {tr('思维导图')} · {formatDateTime(map.trashedAt, state.settings.language)}
                </span>
              </div>
              <button
                type="button"
                className="small-btn"
                onClick={() =>
                  actions.updateMap({ ...map, trashedAt: 0 })
                }
              >
                <RestoreGlyph size={13} /> {tr('恢复')}
              </button>
              <button type="button" className="small-btn danger" onClick={() => actions.deleteMapForever(map.id)}>
                {tr('永久删除')}
              </button>
            </div>
          ))}
        </div>

        <div className="dialog-foot">
          <span className="foot-hint">
            {derived.trashNotes.length + derived.trashMaps.length} {tr('个项目')}
          </span>
          {confirmEmpty ? (
            <>
              <span className="foot-hint danger-text">{tr('清空后无法恢复，确定吗？')}</span>
              <button
                type="button"
                className="small-btn"
                onClick={() => {
                  setConfirmEmpty(false);
                  actions.setTrashOpen(false);
                  actions.emptyTrash();
                }}
              >
                {tr('确认清空')}
              </button>
              <button type="button" className="small-btn" onClick={() => setConfirmEmpty(false)}>
                {tr('取消')}
              </button>
            </>
          ) : (
            <button
              type="button"
              className="small-btn danger"
              disabled={derived.trashNotes.length + derived.trashMaps.length === 0}
              onClick={() => setConfirmEmpty(true)}
            >
              {tr('清空回收站')}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

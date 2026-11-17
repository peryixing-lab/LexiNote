import React, { useEffect, useMemo, useState } from 'react';
import { useStore } from '../store/AppStore';
import {
  diffNoteVersions,
  formatBytes,
  reasonLabel,
  type CrashRecoveryItem,
  type NoteRevision
} from '../../shared/noteHistory';
import type { NoteItem } from '../../shared/types';
import { displayTitle } from '../core/markdown';

const LIVE_CURRENT_ID = '__live_current__';
const CONFLICT_LOCAL_ID = '__conflict_local__';
const CONFLICT_REMOTE_ID = '__conflict_remote__';
const CRASH_DRAFT_ID = '__crash_draft__';

interface VersionOption {
  id: string;
  label: string;
  subtitle: string;
  note: Pick<NoteItem, 'title' | 'content' | 'tags'>;
}

export function NoteHistoryModal(): JSX.Element | null {
  const { state, actions, derived } = useStore();
  const { tr } = derived;
  const noteId = state.historyModalNoteId;
  const note = state.notes.find((item) => item.id === noteId);
  const conflict = noteId ? state.noteConflicts[noteId] : undefined;
  const crashItem: CrashRecoveryItem | undefined = noteId
    ? state.crashRecoveries.find((item) => item.noteId === noteId)
    : undefined;

  const [revisions, setRevisions] = useState<NoteRevision[]>([]);
  const [loading, setLoading] = useState(false);
  const [busy, setBusy] = useState(false);
  const [leftId, setLeftId] = useState('');
  const [rightId, setRightId] = useState(LIVE_CURRENT_ID);
  const [onlyDiffs, setOnlyDiffs] = useState(false);

  const loadHistory = async (targetId: string): Promise<void> => {
    if (!targetId || !window.lexi?.history) return;
    setLoading(true);
    try {
      const list = await window.lexi.history.list(targetId);
      setRevisions(list);
      setLeftId((prev) => {
        if (conflict) return CONFLICT_REMOTE_ID;
        if (crashItem) return CRASH_DRAFT_ID;
        if (prev && list.some((r) => r.id === prev)) return prev;
        return list[0]?.id ?? LIVE_CURRENT_ID;
      });
      setRightId(conflict ? CONFLICT_LOCAL_ID : LIVE_CURRENT_ID);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (!noteId) return;
    void loadHistory(noteId);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [noteId]);

  useEffect(() => {
    if (!noteId) return;
    const onKey = (e: KeyboardEvent): void => {
      if (e.key === 'Escape') actions.closeNoteHistory();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [noteId, actions]);

  const versionOptions = useMemo((): VersionOption[] => {
    if (!note) return [];
    const list: VersionOption[] = [
      {
        id: LIVE_CURRENT_ID,
        label: tr('当前编辑器版本'),
        subtitle: displayTitle(note),
        note
      }
    ];
    if (conflict) {
      list.push({
        id: CONFLICT_LOCAL_ID,
        label: tr('本地未合并版本（当前窗口）'),
        subtitle: new Date(conflict.detectedAt).toLocaleString('zh-CN', { hour12: false }),
        note: conflict.localNote
      });
      list.push({
        id: CONFLICT_REMOTE_ID,
        label: tr('其他窗口版本（主库最新）'),
        subtitle: new Date(conflict.remoteNote.updatedAt).toLocaleString('zh-CN', { hour12: false }),
        note: conflict.remoteNote
      });
    }
    if (crashItem) {
      list.push({
        id: CRASH_DRAFT_ID,
        label: tr('异常退出恢复草稿'),
        subtitle: new Date(crashItem.recoveredAt).toLocaleString('zh-CN', { hour12: false }),
        note: crashItem.draft
      });
    }
    for (const rev of revisions) {
      list.push({
        id: rev.id,
        label: `${new Date(rev.savedAt).toLocaleString('zh-CN', { hour12: false })} · ${reasonLabel(rev.reason)}`,
        subtitle: `${rev.snapshot.title || '无标题笔记'} (${formatBytes(rev.byteSize)})`,
        note: rev.snapshot
      });
    }
    return list;
  }, [note, conflict, crashItem, revisions, tr]);

  if (!noteId || !note) return null;

  const leftOpt = versionOptions.find((v) => v.id === leftId) ?? versionOptions[1] ?? versionOptions[0];
  const rightOpt = versionOptions.find((v) => v.id === rightId) ?? versionOptions[0];
  const diff = leftOpt && rightOpt ? diffNoteVersions(leftOpt.note, rightOpt.note) : null;
  const visibleLines = diff
    ? onlyDiffs
      ? diff.lines.filter((line) => line.kind !== 'equal')
      : diff.lines
    : [];

  const handleManualSnapshot = async (): Promise<void> => {
    setBusy(true);
    try {
      await actions.createNoteSnapshot(note.id);
      await loadHistory(note.id);
    } finally {
      setBusy(false);
    }
  };

  const handleRestore = async (revisionId: string): Promise<void> => {
    setBusy(true);
    try {
      await actions.restoreNoteVersion(note.id, revisionId);
      await loadHistory(note.id);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div
      className="modal-backdrop"
      role="presentation"
      onClick={(e) => {
        if (e.target === e.currentTarget) actions.closeNoteHistory();
      }}
    >
      <div className="history-modal" role="dialog" aria-modal="true" aria-label={tr('版本历史与差异对比')}>
        <div className="dialog-head">
          <div>
            <h3>{tr('版本历史与差异对比')} · {displayTitle(note)}</h3>
            <div className="history-subtitle">
              {tr('恢复任意历史版本前，系统会自动将当前版本与未保存草稿备份到历史快照')}
            </div>
          </div>
          <div className="history-head-actions">
            <button
              type="button"
              className="primary-btn"
              disabled={busy}
              onClick={() => void handleManualSnapshot()}
            >
              {tr('保存当前快照')}
            </button>
            <button type="button" className="small-btn" onClick={() => actions.closeNoteHistory()}>
              {tr('关闭')}
            </button>
          </div>
        </div>

        {conflict ? (
          <div className="history-alert history-alert-warn">
            <div className="history-alert-copy">
              <strong>{tr('检测到多窗口同时修改冲突')}</strong>
              <span>{tr('另一个窗口在您保存前更新了此笔记。已在上方对比“其他窗口版本”与“本地未合并版本”。')}</span>
            </div>
            <div className="history-alert-actions">
              <button
                type="button"
                className="primary-btn"
                disabled={busy}
                onClick={() => void actions.resolveNoteConflict(note.id, 'use-mine-backup-theirs')}
              >
                {tr('保留我的（对方存入历史）')}
              </button>
              <button
                type="button"
                className="small-btn"
                disabled={busy}
                onClick={() => void actions.resolveNoteConflict(note.id, 'use-theirs-backup-mine')}
              >
                {tr('采用对方（我的存入历史）')}
              </button>
              <button
                type="button"
                className="small-btn"
                disabled={busy}
                onClick={() => void actions.resolveNoteConflict(note.id, 'save-copy')}
              >
                {tr('保留为冲突副本')}
              </button>
            </div>
          </div>
        ) : null}

        {crashItem ? (
          <div className="history-alert history-alert-info">
            <div className="history-alert-copy">
              <strong>{tr('发现异常退出前保留的未保存草稿')}</strong>
              <span>{tr('记录时间：{0}', [new Date(crashItem.recoveredAt).toLocaleString('zh-CN', { hour12: false })])}</span>
            </div>
            <div className="history-alert-actions">
              <button
                type="button"
                className="primary-btn"
                disabled={busy}
                onClick={() => void actions.restoreCrashRecovery(crashItem)}
              >
                {tr('恢复该崩溃草稿')}
              </button>
              <button
                type="button"
                className="small-btn"
                disabled={busy}
                onClick={() => void actions.dismissCrashRecovery(note.id)}
              >
                {tr('保留当前版本')}
              </button>
            </div>
          </div>
        ) : null}

        <div className="history-body">
          <div className="history-list-col">
            <div className="history-col-title">{tr('历史快照 ({0})', [revisions.length])}</div>
            <div className="history-rev-scroll">
              {loading ? (
                <div className="history-empty">{tr('正在读取版本快照…')}</div>
              ) : revisions.length === 0 ? (
                <div className="history-empty">{tr('暂无历史快照，可点击右上角“保存当前快照”或继续编辑自动生成')}</div>
              ) : (
                revisions.map((rev) => {
                  const selectedLeft = leftId === rev.id;
                  const selectedRight = rightId === rev.id;
                  return (
                    <div
                      key={rev.id}
                      className={`history-rev-card${selectedLeft || selectedRight ? ' selected' : ''}`}
                      onClick={() => setLeftId(rev.id)}
                    >
                      <div className="history-rev-top">
                        <span className="history-reason-badge">{reasonLabel(rev.reason)}</span>
                        <span className="history-rev-size">{formatBytes(rev.byteSize)}</span>
                      </div>
                      <div className="history-rev-time">
                        {new Date(rev.savedAt).toLocaleString('zh-CN', { hour12: false })}
                      </div>
                      <div className="history-rev-preview">
                        {rev.snapshot.title || tr('无标题笔记')} · {(rev.snapshot.content || '').slice(0, 48).replace(/\s+/g, ' ')}
                      </div>
                      <div className="history-rev-btns">
                        <button
                          type="button"
                          className="small-btn"
                          onClick={(e) => {
                            e.stopPropagation();
                            setLeftId(rev.id);
                          }}
                        >
                          {selectedLeft ? '✓ 版本 A' : '设为 A'}
                        </button>
                        <button
                          type="button"
                          className="small-btn"
                          onClick={(e) => {
                            e.stopPropagation();
                            setRightId(rev.id);
                          }}
                        >
                          {selectedRight ? '✓ 版本 B' : '设为 B'}
                        </button>
                        <button
                          type="button"
                          className="primary-btn"
                          disabled={busy}
                          onClick={(e) => {
                            e.stopPropagation();
                            void handleRestore(rev.id);
                          }}
                        >
                          {tr('恢复此版')}
                        </button>
                      </div>
                    </div>
                  );
                })
              )}
            </div>
          </div>

          <div className="history-diff-col">
            <div className="history-diff-controls">
              <label className="history-select-wrap">
                <span>{tr('版本 A（基准）')}</span>
                <select value={leftId} onChange={(e) => setLeftId(e.target.value)}>
                  {versionOptions.map((opt) => (
                    <option key={opt.id} value={opt.id}>
                      {opt.label}
                    </option>
                  ))}
                </select>
              </label>
              <label className="history-select-wrap">
                <span>{tr('版本 B（对比）')}</span>
                <select value={rightId} onChange={(e) => setRightId(e.target.value)}>
                  {versionOptions.map((opt) => (
                    <option key={opt.id} value={opt.id}>
                      {opt.label}
                    </option>
                  ))}
                </select>
              </label>
              <label className="history-diff-filter">
                <input type="checkbox" checked={onlyDiffs} onChange={(e) => setOnlyDiffs(e.target.checked)} />
                <span>{tr('仅显示差异行')}</span>
              </label>
            </div>

            {diff ? (
              <>
                <div className="history-diff-stats">
                  <span className="diff-stat-add">+{diff.addedCount} {tr('新增')}</span>
                  <span className="diff-stat-del">-{diff.removedCount} {tr('删除')}</span>
                  <span className="diff-stat-eq">{diff.unchangedCount} {tr('未变')}</span>
                  {diff.titleChanged ? (
                    <span className="diff-stat-meta">
                      {tr('标题')}：「{diff.oldTitle || '无标题'}」→「{diff.newTitle || '无标题'}」
                    </span>
                  ) : null}
                  {diff.tagsChanged ? (
                    <span className="diff-stat-meta">
                      {tr('标签')}：[{diff.oldTags.join(', ')}] → [{diff.newTags.join(', ')}]
                    </span>
                  ) : null}
                </div>

                <div className="history-diff-view">
                  {visibleLines.length === 0 ? (
                    <div className="history-empty">{tr('两个版本内容完全一致')}</div>
                  ) : (
                    visibleLines.map((line, idx) => (
                      <div key={idx} className={`diff-line diff-line-${line.kind}`}>
                        <span className="diff-ln">{line.oldLine > 0 ? line.oldLine : ''}</span>
                        <span className="diff-ln">{line.newLine > 0 ? line.newLine : ''}</span>
                        <span className="diff-sign">
                          {line.kind === 'add' ? '+' : line.kind === 'remove' ? '-' : ' '}
                        </span>
                        <span className="diff-text">{line.text || ' '}</span>
                      </div>
                    ))
                  )}
                </div>
              </>
            ) : null}
          </div>
        </div>
      </div>
    </div>
  );
}

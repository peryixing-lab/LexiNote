import type { NoteItem, NoteProperty } from './types';

export type RevisionReason =
  | 'autosave'
  | 'manual'
  | 'restore-backup'
  | 'conflict-backup'
  | 'crash-recovery';

export interface HistoryRetentionPolicy {
  maxAgeDays: number;
  maxCountPerNote: number;
  maxBytesPerNote: number;
  maxTotalBytes: number;
}

export interface NoteRevision {
  id: string;
  noteId: string;
  savedAt: number;
  reason: RevisionReason;
  contentHash: string;
  byteSize: number;
  snapshot: NoteItem;
}

export interface HistoryUsageSummary {
  noteCount: number;
  revisionCount: number;
  totalBytes: number;
}

export interface DiffLine {
  kind: 'equal' | 'add' | 'remove';
  oldLine: number;
  newLine: number;
  text: string;
}

export interface DiffResult {
  titleChanged: boolean;
  oldTitle: string;
  newTitle: string;
  tagsChanged: boolean;
  oldTags: string[];
  newTags: string[];
  addedCount: number;
  removedCount: number;
  unchangedCount: number;
  lines: DiffLine[];
}

export interface DraftWalEntry {
  noteId: string;
  vaultId: string;
  projectId: string;
  title: string;
  content: string;
  tags: string[];
  properties: NoteProperty[];
  baseHash: string;
  baseUpdatedAt: number;
  updatedAt: number;
}

export interface NoteConflictInfo {
  noteId: string;
  detectedAt: number;
  baseHash: string;
  localNote: NoteItem;
  remoteNote: NoteItem;
}

export interface CrashRecoveryItem {
  noteId: string;
  recoveredAt: number;
  isNewNote: boolean;
  draft: NoteItem;
}

export type ConflictResolutionMode =
  | 'use-mine-backup-theirs'
  | 'use-theirs-backup-mine'
  | 'save-copy';

const MILLIS_PER_DAY = 24 * 60 * 60 * 1000;

export const DEFAULT_HISTORY_POLICY: HistoryRetentionPolicy = {
  maxAgeDays: 30,
  maxCountPerNote: 30,
  maxBytesPerNote: 2 * 1024 * 1024,
  maxTotalBytes: 50 * 1024 * 1024
};

export function clampHistoryPolicy(raw?: Partial<HistoryRetentionPolicy> | null): HistoryRetentionPolicy {
  return {
    maxAgeDays: Math.max(1, Math.min(365, Math.round(raw?.maxAgeDays ?? DEFAULT_HISTORY_POLICY.maxAgeDays))),
    maxCountPerNote: Math.max(3, Math.min(200, Math.round(raw?.maxCountPerNote ?? DEFAULT_HISTORY_POLICY.maxCountPerNote))),
    maxBytesPerNote: Math.max(
      256 * 1024,
      Math.min(20 * 1024 * 1024, Math.round(raw?.maxBytesPerNote ?? DEFAULT_HISTORY_POLICY.maxBytesPerNote))
    ),
    maxTotalBytes: Math.max(
      1024 * 1024,
      Math.min(500 * 1024 * 1024, Math.round(raw?.maxTotalBytes ?? DEFAULT_HISTORY_POLICY.maxTotalBytes))
    )
  };
}

export function utf8ByteLength(text: string): number {
  let bytes = 0;
  for (let i = 0; i < text.length; i++) {
    const code = text.charCodeAt(i);
    if (code <= 0x7f) bytes += 1;
    else if (code <= 0x7ff) bytes += 2;
    else if (code >= 0xd800 && code <= 0xdbff) {
      bytes += 4;
      i += 1;
    } else bytes += 3;
  }
  return bytes;
}

export function fnv1aHex(text: string): string {
  let hash = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) {
    hash ^= text.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193);
  }
  return (hash >>> 0).toString(16).padStart(8, '0');
}

export function cloneNote(note: NoteItem): NoteItem {
  return {
    ...note,
    tags: [...(note.tags ?? [])],
    properties: (note.properties ?? []).map((p) => ({ key: p.key, value: p.value }))
  };
}

export function snapshotSignature(note: Pick<NoteItem, 'title' | 'content' | 'tags' | 'properties'>): string {
  const props = (note.properties ?? []).map((p) => `${p.key}=${p.value}`).join('|');
  const tags = (note.tags ?? []).join(',');
  return `${note.title ?? ''}\n---\n${tags}\n---\n${props}\n---\n${note.content ?? ''}`;
}

export function computeSnapshotHash(note: Pick<NoteItem, 'title' | 'content' | 'tags' | 'properties'>): string {
  return fnv1aHex(snapshotSignature(note));
}

export function sameNoteContent(a: Pick<NoteItem, 'title' | 'content' | 'tags' | 'properties'>, b: Pick<NoteItem, 'title' | 'content' | 'tags' | 'properties'>): boolean {
  return snapshotSignature(a) === snapshotSignature(b);
}

export function computeRevisionBytes(snapshot: NoteItem): number {
  return Math.max(utf8ByteLength(JSON.stringify(snapshot)), 64);
}

export function normalizeRevision(raw: Partial<NoteRevision> & { snapshot?: NoteItem }): NoteRevision {
  const snapshot: NoteItem = raw.snapshot ? cloneNote(raw.snapshot) : {
    id: raw.noteId ?? '',
    vaultId: '',
    projectId: '',
    title: '',
    notebook: '默认',
    content: '',
    noteType: 'markdown' as const,
    editorLevel: 'pro' as const,
    tags: [],
    properties: [],
    pinned: false,
    favorite: false,
    trashedAt: 0,
    createdAt: Date.now(),
    updatedAt: Date.now(),
    path: ''
  };
  return {
    id: raw.id || `rev-${Date.now()}-${Math.random().toString(16).slice(2, 8)}`,
    noteId: raw.noteId || snapshot.id,
    savedAt: raw.savedAt && raw.savedAt > 0 ? raw.savedAt : snapshot.updatedAt || Date.now(),
    reason: raw.reason || 'autosave',
    contentHash: raw.contentHash || computeSnapshotHash(snapshot),
    byteSize: raw.byteSize && raw.byteSize > 0 ? raw.byteSize : computeRevisionBytes(snapshot),
    snapshot
  };
}

export function buildRevision(
  id: string,
  snapshot: NoteItem,
  savedAt: number,
  reason: RevisionReason = 'autosave'
): NoteRevision {
  const cloned = cloneNote(snapshot);
  return {
    id,
    noteId: cloned.id,
    savedAt: savedAt > 0 ? savedAt : Date.now(),
    reason,
    contentHash: computeSnapshotHash(cloned),
    byteSize: computeRevisionBytes(cloned),
    snapshot: cloned
  };
}

export function pruneNoteRevisions(
  revisions: NoteRevision[],
  policyInput?: Partial<HistoryRetentionPolicy> | null,
  now = Date.now()
): NoteRevision[] {
  const policy = clampHistoryPolicy(policyInput);
  const cutoff = now - policy.maxAgeDays * MILLIS_PER_DAY;
  const sorted = revisions
    .map((rev) => normalizeRevision(rev))
    .filter((rev) => rev.savedAt >= cutoff)
    .sort((a, b) => b.savedAt - a.savedAt);

  const kept: NoteRevision[] = [];
  let bytes = 0;
  for (const rev of sorted) {
    if (kept.length >= policy.maxCountPerNote) break;
    // Always preserve at least the latest revision unless expired.
    if (kept.length > 0 && bytes + rev.byteSize > policy.maxBytesPerNote) break;
    kept.push(rev);
    bytes += rev.byteSize;
  }
  return kept;
}

export function appendAndPruneRevisions(
  existing: NoteRevision[],
  candidate: NoteRevision,
  policyInput?: Partial<HistoryRetentionPolicy> | null,
  now = Date.now(),
  preserveDuplicate = false
): NoteRevision[] {
  const sorted = existing
    .map((rev) => normalizeRevision(rev))
    .sort((a, b) => b.savedAt - a.savedAt);
  const next = normalizeRevision(candidate);
  if (!preserveDuplicate && sorted.length > 0 && sameNoteContent(sorted[0].snapshot, next.snapshot)) {
    if (next.reason !== 'autosave' && sorted[0].reason === 'autosave') {
      sorted[0] = {
        ...sorted[0],
        reason: next.reason,
        savedAt: Math.max(sorted[0].savedAt, next.savedAt)
      };
    }
    return pruneNoteRevisions(sorted, policyInput, now);
  }
  return pruneNoteRevisions([next, ...sorted], policyInput, now);
}

export function pruneGlobalHistoryMap(
  map: Map<string, NoteRevision[]>,
  policyInput?: Partial<HistoryRetentionPolicy> | null,
  now = Date.now()
): { map: Map<string, NoteRevision[]>; removedCount: number; totalBytes: number } {
  const policy = clampHistoryPolicy(policyInput);
  let beforeCount = 0;
  const working = new Map<string, NoteRevision[]>();
  for (const [noteId, list] of map.entries()) {
    beforeCount += list.length;
    const pruned = pruneNoteRevisions(list, policy, now);
    if (pruned.length > 0) working.set(noteId, pruned);
  }

  let totalBytes = 0;
  for (const list of working.values()) {
    for (const rev of list) totalBytes += rev.byteSize;
  }

  while (totalBytes > policy.maxTotalBytes) {
    let oldestKey = '';
    let oldestTime = Number.POSITIVE_INFINITY;
    for (const [noteId, list] of working.entries()) {
      const last = list[list.length - 1];
      if (last && last.savedAt < oldestTime) {
        oldestTime = last.savedAt;
        oldestKey = noteId;
      }
    }
    if (!oldestKey) break;
    const targetList = working.get(oldestKey);
    if (!targetList || targetList.length === 0) break;
    const popped = targetList.pop()!;
    totalBytes -= popped.byteSize;
    if (targetList.length === 0) working.delete(oldestKey);
  }

  let afterCount = 0;
  for (const list of working.values()) afterCount += list.length;
  return { map: working, removedCount: Math.max(0, beforeCount - afterCount), totalBytes };
}

export function summarizeHistoryMap(map: Map<string, NoteRevision[]>): HistoryUsageSummary {
  let noteCount = 0;
  let revisionCount = 0;
  let totalBytes = 0;
  for (const list of map.values()) {
    if (list.length === 0) continue;
    noteCount += 1;
    revisionCount += list.length;
    for (const rev of list) totalBytes += normalizeRevision(rev).byteSize;
  }
  return { noteCount, revisionCount, totalBytes };
}

function computeLineDiff(oldLines: string[], newLines: string[]): DiffLine[] {
  const n = oldLines.length;
  const m = newLines.length;
  let prefix = 0;
  while (prefix < n && prefix < m && oldLines[prefix] === newLines[prefix]) {
    prefix += 1;
  }
  let suffix = 0;
  while (suffix < n - prefix && suffix < m - prefix && oldLines[n - 1 - suffix] === newLines[m - 1 - suffix]) {
    suffix += 1;
  }

  const lines: DiffLine[] = [];
  for (let i = 0; i < prefix; i++) {
    lines.push({ kind: 'equal', oldLine: i + 1, newLine: i + 1, text: oldLines[i] });
  }

  const midOld = oldLines.slice(prefix, n - suffix);
  const midNew = newLines.slice(prefix, m - suffix);
  const aLen = midOld.length;
  const bLen = midNew.length;

  if (aLen === 0 && bLen === 0) {
    for (let s = 0; s < suffix; s++) {
      lines.push({
        kind: 'equal',
        oldLine: n - suffix + s + 1,
        newLine: m - suffix + s + 1,
        text: oldLines[n - suffix + s]
      });
    }
    return lines;
  }

  if (aLen * bLen > 45000) {
    for (let i = 0; i < aLen; i++) {
      lines.push({ kind: 'remove', oldLine: prefix + i + 1, newLine: 0, text: midOld[i] });
    }
    for (let j = 0; j < bLen; j++) {
      lines.push({ kind: 'add', oldLine: 0, newLine: prefix + j + 1, text: midNew[j] });
    }
  } else {
    const dp: number[][] = Array.from({ length: aLen + 1 }, () => new Array<number>(bLen + 1).fill(0));
    for (let i = aLen - 1; i >= 0; i--) {
      for (let j = bLen - 1; j >= 0; j--) {
        if (midOld[i] === midNew[j]) dp[i][j] = dp[i + 1][j + 1] + 1;
        else dp[i][j] = Math.max(dp[i + 1][j], dp[i][j + 1]);
      }
    }
    let i = 0;
    let j = 0;
    while (i < aLen && j < bLen) {
      if (midOld[i] === midNew[j]) {
        lines.push({ kind: 'equal', oldLine: prefix + i + 1, newLine: prefix + j + 1, text: midOld[i] });
        i += 1;
        j += 1;
      } else if (dp[i + 1][j] >= dp[i][j + 1]) {
        lines.push({ kind: 'remove', oldLine: prefix + i + 1, newLine: 0, text: midOld[i] });
        i += 1;
      } else {
        lines.push({ kind: 'add', oldLine: 0, newLine: prefix + j + 1, text: midNew[j] });
        j += 1;
      }
    }
    while (i < aLen) {
      lines.push({ kind: 'remove', oldLine: prefix + i + 1, newLine: 0, text: midOld[i] });
      i += 1;
    }
    while (j < bLen) {
      lines.push({ kind: 'add', oldLine: 0, newLine: prefix + j + 1, text: midNew[j] });
      j += 1;
    }
  }

  for (let s = 0; s < suffix; s++) {
    lines.push({
      kind: 'equal',
      oldLine: n - suffix + s + 1,
      newLine: m - suffix + s + 1,
      text: oldLines[n - suffix + s]
    });
  }
  return lines;
}

export function diffNoteVersions(
  oldNote: Pick<NoteItem, 'title' | 'content' | 'tags'>,
  newNote: Pick<NoteItem, 'title' | 'content' | 'tags'>
): DiffResult {
  const oldLines = (oldNote.content ?? '').length === 0 ? [] : (oldNote.content ?? '').split('\n');
  const newLines = (newNote.content ?? '').length === 0 ? [] : (newNote.content ?? '').split('\n');
  const lines = computeLineDiff(oldLines, newLines);
  let addedCount = 0;
  let removedCount = 0;
  let unchangedCount = 0;
  for (const line of lines) {
    if (line.kind === 'add') addedCount += 1;
    else if (line.kind === 'remove') removedCount += 1;
    else unchangedCount += 1;
  }
  return {
    titleChanged: (oldNote.title ?? '').trim() !== (newNote.title ?? '').trim(),
    oldTitle: oldNote.title ?? '',
    newTitle: newNote.title ?? '',
    tagsChanged: (oldNote.tags ?? []).join(',') !== (newNote.tags ?? []).join(','),
    oldTags: [...(oldNote.tags ?? [])],
    newTags: [...(newNote.tags ?? [])],
    addedCount,
    removedCount,
    unchangedCount,
    lines
  };
}

export function reasonLabel(reason: RevisionReason | string): string {
  switch (reason) {
    case 'manual':
      return '手动快照';
    case 'restore-backup':
      return '恢复前自动备份';
    case 'conflict-backup':
      return '多窗口冲突备份';
    case 'crash-recovery':
      return '异常退出恢复';
    default:
      return '自动保存';
  }
}

export function formatBytes(bytes: number): string {
  if (!bytes || bytes <= 0) return '0 B';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

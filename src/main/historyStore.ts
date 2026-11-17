import { randomUUID } from 'node:crypto';
import { existsSync, promises as fs } from 'node:fs';
import path from 'node:path';
import type { NoteItem, PersistedState } from '../shared/types';
import {
  appendAndPruneRevisions,
  buildRevision,
  clampHistoryPolicy,
  cloneNote,
  computeSnapshotHash,
  pruneGlobalHistoryMap,
  sameNoteContent,
  summarizeHistoryMap,
  type CrashRecoveryItem,
  type DraftWalEntry,
  type HistoryRetentionPolicy,
  type HistoryUsageSummary,
  type NoteConflictInfo,
  type NoteRevision,
  type RevisionReason
} from '../shared/noteHistory';
import { atomicWriteTextAsync, friendlySaveError, isDiskFullError } from './workspaceFs';

export interface HistoryIoDriver {
  writeAtomic: (filePath: string, content: string) => Promise<void>;
}

const DEFAULT_DRIVER: HistoryIoDriver = {
  writeAtomic: atomicWriteTextAsync
};

function sanitizeFileKey(noteId: string): string {
  const cleaned = noteId.replace(/[^A-Za-z0-9._-]/g, '_');
  return cleaned || 'note';
}

function mergeNoteAccessedAt(
  masterMap: Record<string, number> | undefined,
  incomingMap: Record<string, number> | undefined,
  notes: NoteItem[],
  allowDeletes: boolean
): Record<string, number> | undefined {
  const merged: Record<string, number> = {};
  const validIds = allowDeletes ? new Set(notes.map((n) => n.id)) : null;
  const apply = (source?: Record<string, number>) => {
    if (!source) return;
    for (const [id, raw] of Object.entries(source)) {
      if (validIds && !validIds.has(id)) continue;
      if (typeof raw === 'number' && Number.isFinite(raw) && raw > 0) {
        merged[id] = Math.max(merged[id] ?? 0, raw);
      }
    }
  };
  apply(masterMap);
  apply(incomingMap);
  return Object.keys(merged).length > 0 ? merged : undefined;
}

export function mergeWithConflictDetection(
  master: PersistedState,
  incoming: PersistedState,
  allowDeletes: boolean,
  noteBases: Record<string, string> | undefined,
  mergeSimpleFn: <T extends { id: string }>(m: T[], inc: T[], allowDel: boolean) => T[],
  mergeUpdatedFn: <T extends { id: string }>(
    m: T[],
    inc: T[],
    updatedAt: (item: T) => number,
    allowDel: boolean
  ) => T[]
): {
  merged: PersistedState;
  conflicts: NoteConflictInfo[];
  replacedMasterNotes: NoteItem[];
} {
  const incomingById = new Map(incoming.notes.map((n) => [n.id, n]));
  const masterIds = new Set(master.notes.map((n) => n.id));
  const nextNotes: NoteItem[] = [];
  const conflicts: NoteConflictInfo[] = [];
  const replacedMasterNotes: NoteItem[] = [];

  for (const masterNote of master.notes) {
    const inc = incomingById.get(masterNote.id);
    if (!inc) {
      if (!allowDeletes) nextNotes.push(masterNote);
      else replacedMasterNotes.push(masterNote);
      continue;
    }

    const masterHash = computeSnapshotHash(masterNote);
    const incHash = computeSnapshotHash(inc);
    if (masterHash === incHash) {
      // Metadata-only or no-op save: prefer newer updatedAt / incoming non-destructive flags.
      nextNotes.push(inc.updatedAt >= masterNote.updatedAt ? inc : masterNote);
      continue;
    }

    const senderBaseHash = noteBases?.[masterNote.id];
    // Concurrent modification detected when sender started from an older snapshot than master.
    if (senderBaseHash && senderBaseHash !== masterHash) {
      conflicts.push({
        noteId: masterNote.id,
        detectedAt: Date.now(),
        baseHash: senderBaseHash,
        localNote: cloneNote(inc),
        remoteNote: cloneNote(masterNote)
      });
      // Keep committed master on disk until user picks resolution; caller backs up inc to history.
      nextNotes.push(masterNote);
      continue;
    }

    // Fast-forward: if snapshot is stale without base matching, protect newer master unless sender is strictly based on master.
    if (!senderBaseHash && !allowDeletes && inc.updatedAt < masterNote.updatedAt) {
      conflicts.push({
        noteId: masterNote.id,
        detectedAt: Date.now(),
        baseHash: '',
        localNote: cloneNote(inc),
        remoteNote: cloneNote(masterNote)
      });
      nextNotes.push(masterNote);
      continue;
    }

    replacedMasterNotes.push(masterNote);
    nextNotes.push(inc);
  }

  for (const inc of incoming.notes) {
    if (!masterIds.has(inc.id)) nextNotes.push(inc);
  }

  const newerSettings =
    (incoming.settings?.settingsUpdatedAt ?? 0) >= (master.settings?.settingsUpdatedAt ?? 0)
      ? incoming.settings
      : master.settings;

  const nextAccessed = mergeNoteAccessedAt(master.noteAccessedAt, incoming.noteAccessedAt, nextNotes, allowDeletes);

  return {
    merged: {
      version: 2,
      vaults: mergeSimpleFn(master.vaults, incoming.vaults, allowDeletes),
      projects: mergeSimpleFn(master.projects, incoming.projects, allowDeletes),
      notes: nextNotes,
      maps: mergeUpdatedFn(master.maps, incoming.maps, (m) => m.updatedAt, allowDeletes),
      canvases: mergeUpdatedFn(master.canvases, incoming.canvases, (c) => c.updatedAt, allowDeletes),
      settings: newerSettings,
      ...(nextAccessed ? { noteAccessedAt: nextAccessed } : {})
    },
    conflicts,
    replacedMasterNotes
  };
}

export class NoteHistoryStore {
  private readonly historyDir: string;
  private readonly walDir: string;
  private readonly pendingCrashFile: string;
  private readonly io: HistoryIoDriver;
  private queue: Promise<unknown> = Promise.resolve();

  constructor(private readonly userDataDir: string, io: HistoryIoDriver = DEFAULT_DRIVER) {
    this.historyDir = path.join(userDataDir, 'note-history');
    this.walDir = path.join(userDataDir, 'recovery-wal');
    this.pendingCrashFile = path.join(userDataDir, 'pending-crash-recovery.json');
    this.io = io;
  }

  private withLock<T>(task: () => Promise<T>): Promise<T> {
    const next = this.queue.then(task, task);
    this.queue = next.then(
      () => undefined,
      () => undefined
    );
    return next;
  }

  private historyFile(noteId: string): string {
    return path.join(this.historyDir, `${sanitizeFileKey(noteId)}.json`);
  }

  private walFile(noteId: string): string {
    return path.join(this.walDir, `${sanitizeFileKey(noteId)}.json`);
  }

  private async readJsonSafe<T>(filePath: string, fallback: T): Promise<T> {
    try {
      const raw = await fs.readFile(filePath, 'utf8');
      return JSON.parse(raw) as T;
    } catch (error) {
      const err = error as NodeJS.ErrnoException;
      if (err?.code !== 'ENOENT') {
        try {
          await fs.rename(filePath, `${filePath}.corrupt-${Date.now()}`);
        } catch {
          // Keep fallback if rename is not possible.
        }
      }
      return fallback;
    }
  }

  private async loadAllHistoryMap(): Promise<Map<string, NoteRevision[]>> {
    const map = new Map<string, NoteRevision[]>();
    if (!existsSync(this.historyDir)) return map;
    const files = await fs.readdir(this.historyDir);
    for (const file of files) {
      if (!file.endsWith('.json') || file.includes('.corrupt-')) continue;
      const full = path.join(this.historyDir, file);
      const parsed = await this.readJsonSafe<NoteRevision[]>(full, []);
      if (!Array.isArray(parsed) || parsed.length === 0) continue;
      const noteId = parsed[0]?.noteId || parsed[0]?.snapshot?.id || file.replace(/\.json$/, '');
      map.set(noteId, parsed);
    }
    return map;
  }

  private async saveMapDiff(
    prevKeys: Iterable<string>,
    nextMap: Map<string, NoteRevision[]>
  ): Promise<void> {
    await fs.mkdir(this.historyDir, { recursive: true });
    for (const [noteId, revs] of nextMap.entries()) {
      await this.io.writeAtomic(this.historyFile(noteId), JSON.stringify(revs));
    }
    for (const oldKey of prevKeys) {
      if (!nextMap.has(oldKey)) {
        try {
          await fs.unlink(this.historyFile(oldKey));
        } catch {
          // Already removed.
        }
      }
    }
  }

  async getNoteHistory(noteId: string): Promise<NoteRevision[]> {
    const list = await this.readJsonSafe<NoteRevision[]>(this.historyFile(noteId), []);
    if (!Array.isArray(list)) return [];
    return list.slice().sort((a, b) => b.savedAt - a.savedAt);
  }

  async getUsage(): Promise<HistoryUsageSummary> {
    const map = await this.loadAllHistoryMap();
    return summarizeHistoryMap(map);
  }

  async pruneAll(policyInput?: Partial<HistoryRetentionPolicy> | null): Promise<{ removedCount: number; summary: HistoryUsageSummary }> {
    return this.withLock(async () => {
      const map = await this.loadAllHistoryMap();
      const prevKeys = [...map.keys()];
      const pruned = pruneGlobalHistoryMap(map, policyInput, Date.now());
      await this.saveMapDiff(prevKeys, pruned.map);
      return {
        removedCount: pruned.removedCount,
        summary: summarizeHistoryMap(pruned.map)
      };
    });
  }

  async recordSnapshot(
    snapshot: NoteItem,
    reason: RevisionReason = 'autosave',
    policyInput?: Partial<HistoryRetentionPolicy> | null,
    preserveDuplicate = false
  ): Promise<{ revision: NoteRevision | null; warning?: string }> {
    return this.withLock(async () => this.recordSnapshotUnlocked(snapshot, reason, policyInput, preserveDuplicate));
  }

  private async recordSnapshotUnlocked(
    snapshot: NoteItem,
    reason: RevisionReason,
    policyInput?: Partial<HistoryRetentionPolicy> | null,
    preserveDuplicate = false
  ): Promise<{ revision: NoteRevision | null; warning?: string }> {
    const policy = clampHistoryPolicy(policyInput);
    const rev = buildRevision(`rev-${randomUUID()}`, snapshot, Date.now(), reason);
    const map = await this.loadAllHistoryMap();
    const prevKeys = [...map.keys()];
    const existing = map.get(snapshot.id) ?? [];
    const perNote = appendAndPruneRevisions(existing, rev, policy, Date.now(), preserveDuplicate);
    map.set(snapshot.id, perNote);
    const globalResult = pruneGlobalHistoryMap(map, policy, Date.now());

    try {
      await this.saveMapDiff(prevKeys, globalResult.map);
      const updated = globalResult.map.get(snapshot.id) ?? [];
      return { revision: updated[0] ?? rev };
    } catch (error) {
      if (isDiskFullError(error)) {
        // Under disk pressure, aggressively compact old history so primary saves do not lose data.
        try {
          const tightPolicy: HistoryRetentionPolicy = {
            maxAgeDays: 7,
            maxCountPerNote: 3,
            maxBytesPerNote: 512 * 1024,
            maxTotalBytes: 2 * 1024 * 1024
          };
          const compacted = pruneGlobalHistoryMap(map, tightPolicy, Date.now());
          await this.saveMapDiff(prevKeys, compacted.map);
          const updated = compacted.map.get(snapshot.id) ?? [];
          return {
            revision: updated[0] ?? null,
            warning: '磁盘空间紧张，已自动精简较旧历史快照以优先保障当前笔记保存'
          };
        } catch (retryErr) {
          return {
            revision: null,
            warning: `历史快照写入受限（${friendlySaveError(retryErr)}），当前主笔记内容已保留`
          };
        }
      }
      throw error;
    }
  }

  async restoreRevision(
    currentSavedNote: NoteItem,
    revisionId: string,
    liveDraft: Pick<NoteItem, 'title' | 'content' | 'tags' | 'properties'> | null | undefined,
    policyInput?: Partial<HistoryRetentionPolicy> | null
  ): Promise<{ restoredNote: NoteItem; revisions: NoteRevision[]; warning?: string }> {
    return this.withLock(async () => {
      const history = await this.readJsonSafe<NoteRevision[]>(this.historyFile(currentSavedNote.id), []);
      const target = history.find((rev) => rev.id === revisionId);
      if (!target) {
        throw new Error('所选历史快照已不存在');
      }

      const warnings: string[] = [];
      // 1. Always preserve the last saved version before overwriting.
      const saveCurrentRes = await this.recordSnapshotUnlocked(currentSavedNote, 'restore-backup', policyInput, true);
      if (saveCurrentRes.warning) warnings.push(saveCurrentRes.warning);

      // 2. If editor had unsaved live edits differing from currentSavedNote, preserve live draft too!
      if (liveDraft) {
        const draftSnap = cloneNote(currentSavedNote);
        draftSnap.title = liveDraft.title;
        draftSnap.content = liveDraft.content;
        draftSnap.tags = [...(liveDraft.tags ?? [])];
        draftSnap.properties = (liveDraft.properties ?? []).map((p) => ({ key: p.key, value: p.value }));
        if (!sameNoteContent(draftSnap, currentSavedNote)) {
          draftSnap.updatedAt = Date.now();
          const draftRes = await this.recordSnapshotUnlocked(draftSnap, 'restore-backup', policyInput, true);
          if (draftRes.warning) warnings.push(draftRes.warning);
        }
      }

      const restored = cloneNote(currentSavedNote);
      restored.title = target.snapshot.title;
      restored.content = target.snapshot.content;
      restored.tags = [...(target.snapshot.tags ?? [])];
      restored.properties = (target.snapshot.properties ?? []).map((p) => ({ key: p.key, value: p.value }));
      restored.updatedAt = Date.now();

      const refreshed = await this.getNoteHistory(currentSavedNote.id);
      return {
        restoredNote: restored,
        revisions: refreshed,
        warning: warnings[0]
      };
    });
  }

  async deleteNoteHistory(noteId: string): Promise<void> {
    await this.withLock(async () => {
      for (const p of [this.historyFile(noteId), this.walFile(noteId)]) {
        try {
          await fs.unlink(p);
        } catch {
          // Ignore missing files.
        }
      }
      await this.dismissCrashRecoveryUnlocked(noteId);
    });
  }

  async writeDraftWal(entry: DraftWalEntry): Promise<void> {
    if (!entry.noteId) return;
    await this.withLock(async () => {
      await fs.mkdir(this.walDir, { recursive: true });
      await this.io.writeAtomic(this.walFile(entry.noteId), JSON.stringify(entry));
    });
  }

  async clearDraftWal(noteIds: string[]): Promise<void> {
    if (noteIds.length === 0) return;
    await this.withLock(async () => {
      for (const noteId of noteIds) {
        try {
          await fs.unlink(this.walFile(noteId));
        } catch {
          // Already absent.
        }
      }
    });
  }

  async listDraftWal(): Promise<DraftWalEntry[]> {
    if (!existsSync(this.walDir)) return [];
    const files = await fs.readdir(this.walDir);
    const out: DraftWalEntry[] = [];
    for (const file of files) {
      if (!file.endsWith('.json') || file.includes('.corrupt-')) continue;
      const entry = await this.readJsonSafe<DraftWalEntry | null>(path.join(this.walDir, file), null);
      if (entry && entry.noteId) out.push(entry);
    }
    return out;
  }

  async recoverCrashDrafts(
    masterState: PersistedState,
    policyInput?: Partial<HistoryRetentionPolicy> | null
  ): Promise<{
    nextState: PersistedState;
    stateChanged: boolean;
    recoveredItems: CrashRecoveryItem[];
  }> {
    return this.withLock(async () => {
      const walEntries = await this.listDraftWal();
      const pending = await this.readPendingCrashListUnlocked();
      if (walEntries.length === 0) {
        return { nextState: masterState, stateChanged: false, recoveredItems: pending };
      }

      const nextNotes = masterState.notes.slice();
      let stateChanged = false;
      const nextPending = pending.slice();
      const fallbackVaultId = masterState.vaults[0]?.id || '';

      for (const entry of walEntries) {
        const idx = nextNotes.findIndex((n) => n.id === entry.noteId);
        if (idx < 0) {
          if (entry.title.trim() || entry.content.trim()) {
            const recovered: NoteItem = {
              id: entry.noteId,
              vaultId: entry.vaultId || fallbackVaultId,
              projectId: entry.projectId || '',
              title: entry.title || '崩溃恢复笔记',
              notebook: '默认',
              content: entry.content,
              noteType: 'markdown',
              editorLevel: 'pro',
              tags: [...(entry.tags ?? [])],
              properties: (entry.properties ?? []).map((p) => ({ key: p.key, value: p.value })),
              pinned: false,
              favorite: false,
              trashedAt: 0,
              createdAt: entry.updatedAt || Date.now(),
              updatedAt: entry.updatedAt || Date.now(),
              path: ''
            };
            nextNotes.unshift(recovered);
            stateChanged = true;
            await this.recordSnapshotUnlocked(recovered, 'crash-recovery', policyInput, true);
            const upsertIdx = nextPending.findIndex((p) => p.noteId === recovered.id);
            const item: CrashRecoveryItem = {
              noteId: recovered.id,
              recoveredAt: Date.now(),
              isNewNote: true,
              draft: cloneNote(recovered)
            };
            if (upsertIdx >= 0) nextPending[upsertIdx] = item;
            else nextPending.unshift(item);
          }
          try {
            await fs.unlink(this.walFile(entry.noteId));
          } catch {
            // Ignore cleanup failure.
          }
          continue;
        }

        const existing = nextNotes[idx];
        const draftNote: NoteItem = {
          ...cloneNote(existing),
          title: entry.title,
          content: entry.content,
          tags: [...(entry.tags ?? [])],
          properties: (entry.properties ?? []).map((p) => ({ key: p.key, value: p.value })),
          updatedAt: entry.updatedAt || Date.now()
        };

        if (!sameNoteContent(draftNote, existing)) {
          await this.recordSnapshotUnlocked(draftNote, 'crash-recovery', policyInput, true);
          const item: CrashRecoveryItem = {
            noteId: existing.id,
            recoveredAt: Date.now(),
            isNewNote: false,
            draft: draftNote
          };
          const upsertIdx = nextPending.findIndex((p) => p.noteId === existing.id);
          if (upsertIdx >= 0) nextPending[upsertIdx] = item;
          else nextPending.unshift(item);
        }

        try {
          await fs.unlink(this.walFile(entry.noteId));
        } catch {
          // Ignore cleanup failure.
        }
      }

      if (nextPending.length > 0) {
        await this.io.writeAtomic(this.pendingCrashFile, JSON.stringify(nextPending));
      }

      return {
        nextState: stateChanged ? { ...masterState, notes: nextNotes } : masterState,
        stateChanged,
        recoveredItems: nextPending
      };
    });
  }

  async getPendingCrashRecoveries(): Promise<CrashRecoveryItem[]> {
    return this.withLock(async () => this.readPendingCrashListUnlocked());
  }

  async dismissCrashRecovery(noteId: string): Promise<void> {
    await this.withLock(async () => this.dismissCrashRecoveryUnlocked(noteId));
  }

  private async readPendingCrashListUnlocked(): Promise<CrashRecoveryItem[]> {
    const parsed = await this.readJsonSafe<CrashRecoveryItem[]>(this.pendingCrashFile, []);
    return Array.isArray(parsed) ? parsed : [];
  }

  private async dismissCrashRecoveryUnlocked(noteId: string): Promise<void> {
    const list = await this.readPendingCrashListUnlocked();
    const filtered = list.filter((item) => item.noteId !== noteId);
    if (filtered.length === list.length) return;
    if (filtered.length === 0) {
      try {
        await fs.unlink(this.pendingCrashFile);
      } catch {
        // Already absent.
      }
      return;
    }
    await this.io.writeAtomic(this.pendingCrashFile, JSON.stringify(filtered));
  }
}

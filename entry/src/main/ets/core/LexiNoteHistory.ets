import { NoteItem, NoteProperty, NoteRevision } from './LexiModels';

export class LexiHistoryRetentionPolicy {
  maxAgeDays: number = 30;
  maxCountPerNote: number = 30;
  maxBytesPerNote: number = 2 * 1024 * 1024;
  maxTotalBytes: number = 50 * 1024 * 1024;
}

export class LexiHistoryUsageSummary {
  noteCount: number = 0;
  revisionCount: number = 0;
  totalBytes: number = 0;
}

export class LexiHistoryNoteEntry {
  noteId: string = '';
  revisions: NoteRevision[] = [];

  constructor(noteId: string = '', revisions: NoteRevision[] = []) {
    this.noteId = noteId;
    this.revisions = revisions;
  }
}

export class LexiDiffLine {
  kind: string = 'equal'; // 'equal' | 'add' | 'remove'
  oldLine: number = 0;
  newLine: number = 0;
  text: string = '';

  constructor(kind: string, oldLine: number, newLine: number, text: string) {
    this.kind = kind;
    this.oldLine = oldLine;
    this.newLine = newLine;
    this.text = text;
  }
}

export class LexiDiffResult {
  titleChanged: boolean = false;
  oldTitle: string = '';
  newTitle: string = '';
  tagsChanged: boolean = false;
  oldTags: string[] = [];
  newTags: string[] = [];
  addedCount: number = 0;
  removedCount: number = 0;
  unchangedCount: number = 0;
  lines: LexiDiffLine[] = [];
}

export class LexiDraftWalEntry {
  noteId: string = '';
  vaultId: string = '';
  projectId: string = '';
  title: string = '';
  content: string = '';
  notebook: string = '速记收件箱';
  editorLevel: string = 'simple';
  tags: string[] = [];
  properties: NoteProperty[] = [];
  baseTitle: string = '';
  baseContent: string = '';
  baseUpdatedAt: number = 0;
  updatedAt: number = 0;
  windowId: string = '';
}

export class LexiHistoryPruneResult {
  entries: LexiHistoryNoteEntry[] = [];
  removedCount: number = 0;
  totalBytes: number = 0;
}

const MILLIS_PER_DAY = 24 * 60 * 60 * 1000;

export class LexiNoteHistory {
  static defaultPolicy(): LexiHistoryRetentionPolicy {
    return new LexiHistoryRetentionPolicy();
  }

  static clampPolicy(raw: LexiHistoryRetentionPolicy): LexiHistoryRetentionPolicy {
    const policy = new LexiHistoryRetentionPolicy();
    policy.maxAgeDays = Math.max(1, Math.min(365, Math.round(raw.maxAgeDays || 30)));
    policy.maxCountPerNote = Math.max(3, Math.min(200, Math.round(raw.maxCountPerNote || 30)));
    policy.maxBytesPerNote = Math.max(256 * 1024, Math.min(20 * 1024 * 1024, Math.round(raw.maxBytesPerNote || (2 * 1024 * 1024))));
    policy.maxTotalBytes = Math.max(1024 * 1024, Math.min(500 * 1024 * 1024, Math.round(raw.maxTotalBytes || (50 * 1024 * 1024))));
    return policy;
  }

  static utf8Bytes(text: string): number {
    let total = 0;
    for (let i = 0; i < text.length; i++) {
      const code = text.charCodeAt(i);
      if (code <= 0x7f) {
        total += 1;
      } else if (code <= 0x7ff) {
        total += 2;
      } else if (code >= 0xd800 && code <= 0xdbff) {
        total += 4;
        i += 1;
      } else {
        total += 3;
      }
    }
    return total;
  }

  static fnv1aHex(text: string): string {
    let hash = 0x811c9dc5;
    for (let i = 0; i < text.length; i++) {
      hash ^= text.charCodeAt(i);
      hash = Math.imul(hash, 0x01000193);
    }
    return (hash >>> 0).toString(16).padStart(8, '0');
  }

  static snapshotSignature(note: NoteItem): string {
    const props = (note.properties || [])
      .map((prop: NoteProperty): string => `${prop.key}=${prop.propValue}`)
      .join('|');
    const tags = (note.tags || []).join(',');
    return `${note.title}\n---\n${tags}\n---\n${props}\n---\n${note.content}`;
  }

  static computeSnapshotHash(note: NoteItem): string {
    return LexiNoteHistory.fnv1aHex(LexiNoteHistory.snapshotSignature(note));
  }

  static computeRevisionBytes(snapshot: NoteItem): number {
    const raw = JSON.stringify(snapshot);
    return Math.max(LexiNoteHistory.utf8Bytes(raw), 64);
  }

  static cloneNote(note: NoteItem): NoteItem {
    return JSON.parse(JSON.stringify(note)) as NoteItem;
  }

  static normalizeRevision(raw: NoteRevision): NoteRevision {
    const revision = new NoteRevision();
    revision.id = raw.id || '';
    revision.savedAt = raw.savedAt || (raw.snapshot ? raw.snapshot.updatedAt : 0) || Date.now();
    revision.reason = raw.reason || 'autosave';
    revision.snapshot = raw.snapshot ? LexiNoteHistory.cloneNote(raw.snapshot) : new NoteItem();
    revision.contentHash = raw.contentHash || LexiNoteHistory.computeSnapshotHash(revision.snapshot);
    revision.byteSize = raw.byteSize && raw.byteSize > 0
      ? raw.byteSize
      : LexiNoteHistory.computeRevisionBytes(revision.snapshot);
    return revision;
  }

  static buildRevision(id: string, snapshot: NoteItem, savedAt: number, reason: string = 'autosave'): NoteRevision {
    const revision = new NoteRevision();
    revision.id = id;
    revision.savedAt = savedAt > 0 ? savedAt : Date.now();
    revision.reason = reason || 'autosave';
    revision.snapshot = LexiNoteHistory.cloneNote(snapshot);
    revision.contentHash = LexiNoteHistory.computeSnapshotHash(revision.snapshot);
    revision.byteSize = LexiNoteHistory.computeRevisionBytes(revision.snapshot);
    return revision;
  }

  static sameContent(a: NoteItem, b: NoteItem): boolean {
    if (a.title !== b.title || a.content !== b.content) {
      return false;
    }
    const tagsA = (a.tags || []).join('\u0000');
    const tagsB = (b.tags || []).join('\u0000');
    if (tagsA !== tagsB) {
      return false;
    }
    const propsA = (a.properties || []).map((p: NoteProperty): string => `${p.key}\u0001${p.propValue}`).join('\u0000');
    const propsB = (b.properties || []).map((p: NoteProperty): string => `${p.key}\u0001${p.propValue}`).join('\u0000');
    return propsA === propsB;
  }

  static appendAndPrune(
    existing: NoteRevision[],
    candidate: NoteRevision,
    policy: LexiHistoryRetentionPolicy,
    now: number = Date.now(),
    allowDuplicateReason: boolean = false
  ): NoteRevision[] {
    const normalized = existing.map((item: NoteRevision): NoteRevision => LexiNoteHistory.normalizeRevision(item));
    normalized.sort((a: NoteRevision, b: NoteRevision): number => b.savedAt - a.savedAt);
    const nextCandidate = LexiNoteHistory.normalizeRevision(candidate);
    if (!allowDuplicateReason && normalized.length > 0 &&
      LexiNoteHistory.sameContent(normalized[0].snapshot, nextCandidate.snapshot)) {
      if (nextCandidate.reason !== 'autosave' && normalized[0].reason === 'autosave') {
        normalized[0].reason = nextCandidate.reason;
        normalized[0].savedAt = Math.max(normalized[0].savedAt, nextCandidate.savedAt);
      }
      return LexiNoteHistory.pruneRevisions(normalized, policy, now);
    }
    return LexiNoteHistory.pruneRevisions([nextCandidate].concat(normalized), policy, now);
  }

  static pruneRevisions(
    revisions: NoteRevision[],
    policy: LexiHistoryRetentionPolicy,
    now: number = Date.now()
  ): NoteRevision[] {
    const clamped = LexiNoteHistory.clampPolicy(policy);
    const normalized = revisions
      .map((item: NoteRevision): NoteRevision => LexiNoteHistory.normalizeRevision(item))
      .sort((a: NoteRevision, b: NoteRevision): number => b.savedAt - a.savedAt);
    if (normalized.length === 0) {
      return [];
    }
    const minTimestamp = clamped.maxAgeDays > 0 ? now - clamped.maxAgeDays * MILLIS_PER_DAY : 0;
    const kept: NoteRevision[] = [];
    let usedBytes = 0;
    for (let i = 0; i < normalized.length; i++) {
      const entry = normalized[i];
      if (kept.length >= clamped.maxCountPerNote) {
        break;
      }
      if (minTimestamp > 0 && entry.savedAt > 0 && entry.savedAt < minTimestamp) {
        // Keep only entries within the configured time window.
        continue;
      }
      if (kept.length > 0 && usedBytes + entry.byteSize > clamped.maxBytesPerNote) {
        break;
      }
      kept.push(entry);
      usedBytes += entry.byteSize;
    }
    return kept;
  }

  static pruneAllEntries(
    entries: LexiHistoryNoteEntry[],
    policy: LexiHistoryRetentionPolicy,
    now: number = Date.now()
  ): LexiHistoryPruneResult {
    const clamped = LexiNoteHistory.clampPolicy(policy);
    const result = new LexiHistoryPruneResult();
    const working: LexiHistoryNoteEntry[] = [];
    let totalBytes = 0;

    for (let i = 0; i < entries.length; i++) {
      const entry = entries[i];
      const normalized = entry.revisions.map((rev: NoteRevision): NoteRevision => LexiNoteHistory.normalizeRevision(rev));
      const pruned = LexiNoteHistory.pruneRevisions(normalized, clamped, now);
      result.removedCount += Math.max(0, entry.revisions.length - pruned.length);
      if (pruned.length > 0) {
        working.push(new LexiHistoryNoteEntry(entry.noteId, pruned));
        for (let j = 0; j < pruned.length; j++) {
          totalBytes += pruned[j].byteSize;
        }
      }
    }

    // Evict oldest revisions globally when cumulative size exceeds maxTotalBytes.
    while (totalBytes > clamped.maxTotalBytes) {
      let oldestNoteIdx = -1;
      let oldestRevIdx = -1;
      let oldestTime = Number.MAX_SAFE_INTEGER;
      // First pass: prefer evicting non-latest revisions so each note keeps its newest recovery anchor.
      for (let i = 0; i < working.length; i++) {
        const list = working[i].revisions;
        if (list.length <= 1) { continue; }
        const idx = list.length - 1;
        if (list[idx].savedAt <= oldestTime) {
          oldestTime = list[idx].savedAt;
          oldestNoteIdx = i;
          oldestRevIdx = idx;
        }
      }
      // Second pass: if every remaining note only has 1 revision and still exceeds budget, evict globally oldest.
      if (oldestNoteIdx < 0) {
        for (let i = 0; i < working.length; i++) {
          const list = working[i].revisions;
          if (list.length === 0) { continue; }
          const idx = list.length - 1;
          if (list[idx].savedAt <= oldestTime) {
            oldestTime = list[idx].savedAt;
            oldestNoteIdx = i;
            oldestRevIdx = idx;
          }
        }
      }
      if (oldestNoteIdx < 0 || oldestRevIdx < 0) {
        break;
      }
      const evicted = working[oldestNoteIdx].revisions.splice(oldestRevIdx, 1)[0];
      totalBytes -= evicted ? evicted.byteSize : 0;
      result.removedCount += 1;
    }

    result.entries = working.filter((entry: LexiHistoryNoteEntry): boolean => entry.revisions.length > 0);
    result.totalBytes = Math.max(0, totalBytes);
    return result;
  }

  static summarize(entries: LexiHistoryNoteEntry[]): LexiHistoryUsageSummary {
    const summary = new LexiHistoryUsageSummary();
    for (let i = 0; i < entries.length; i++) {
      if (entries[i].revisions.length === 0) { continue; }
      summary.noteCount += 1;
      for (let j = 0; j < entries[i].revisions.length; j++) {
        const rev = LexiNoteHistory.normalizeRevision(entries[i].revisions[j]);
        summary.revisionCount += 1;
        summary.totalBytes += rev.byteSize;
      }
    }
    return summary;
  }

  static diffVersions(
    oldTitle: string,
    oldContent: string,
    newTitle: string,
    newContent: string,
    oldTags: string[] = [],
    newTags: string[] = []
  ): LexiDiffResult {
    const result = new LexiDiffResult();
    result.oldTitle = oldTitle;
    result.newTitle = newTitle;
    result.titleChanged = oldTitle.trim() !== newTitle.trim();
    result.oldTags = oldTags.slice();
    result.newTags = newTags.slice();
    result.tagsChanged = oldTags.join(',') !== newTags.join(',');

    const oldLines = oldContent.length === 0 ? [] : oldContent.split('\n');
    const newLines = newContent.length === 0 ? [] : newContent.split('\n');
    const rawDiff = LexiNoteHistory.computeLineDiff(oldLines, newLines);
    result.lines = rawDiff;
    for (let i = 0; i < rawDiff.length; i++) {
      if (rawDiff[i].kind === 'add') {
        result.addedCount += 1;
      } else if (rawDiff[i].kind === 'remove') {
        result.removedCount += 1;
      } else {
        result.unchangedCount += 1;
      }
    }
    return result;
  }

  private static computeLineDiff(oldLines: string[], newLines: string[]): LexiDiffLine[] {
    const n = oldLines.length;
    const m = newLines.length;
    if (n === 0 && m === 0) {
      return [];
    }
    // Trim common prefix & suffix first to keep DP tight even on large notes.
    let prefix = 0;
    while (prefix < n && prefix < m && oldLines[prefix] === newLines[prefix]) {
      prefix += 1;
    }
    let suffix = 0;
    while (suffix < n - prefix && suffix < m - prefix &&
      oldLines[n - 1 - suffix] === newLines[m - 1 - suffix]) {
      suffix += 1;
    }

    const lines: LexiDiffLine[] = [];
    for (let i = 0; i < prefix; i++) {
      lines.push(new LexiDiffLine('equal', i + 1, i + 1, oldLines[i]));
    }

    const midOldCount = n - prefix - suffix;
    const midNewCount = m - prefix - suffix;

    if (midOldCount * midNewCount <= 60000) {
      // Exact LCS dynamic programming for crisp line-level diffs.
      const rows = midOldCount + 1;
      const cols = midNewCount + 1;
      const dp: number[] = new Array<number>(rows * cols).fill(0);
      for (let i = midOldCount - 1; i >= 0; i--) {
        const aLine = oldLines[prefix + i];
        for (let j = midNewCount - 1; j >= 0; j--) {
          if (aLine === newLines[prefix + j]) {
            dp[i * cols + j] = dp[(i + 1) * cols + (j + 1)] + 1;
          } else {
            const down = dp[(i + 1) * cols + j];
            const right = dp[i * cols + (j + 1)];
            dp[i * cols + j] = down >= right ? down : right;
          }
        }
      }
      let i = 0;
      let j = 0;
      while (i < midOldCount || j < midNewCount) {
        if (i < midOldCount && j < midNewCount && oldLines[prefix + i] === newLines[prefix + j]) {
          lines.push(new LexiDiffLine('equal', prefix + i + 1, prefix + j + 1, oldLines[prefix + i]));
          i += 1;
          j += 1;
        } else if (j < midNewCount && (i === midOldCount || dp[i * cols + (j + 1)] >= dp[(i + 1) * cols + j])) {
          lines.push(new LexiDiffLine('add', 0, prefix + j + 1, newLines[prefix + j]));
          j += 1;
        } else {
          lines.push(new LexiDiffLine('remove', prefix + i + 1, 0, oldLines[prefix + i]));
          i += 1;
        }
      }
    } else {
      // Linear-memory fallback when middle hunk is huge.
      const anchorMap = new Map<string, number[]>();
      for (let j = 0; j < midNewCount; j++) {
        const key = newLines[prefix + j];
        const bucket = anchorMap.get(key) || [];
        bucket.push(j);
        anchorMap.set(key, bucket);
      }
      let oi = 0;
      let ni = 0;
      while (oi < midOldCount && ni < midNewCount) {
        if (oldLines[prefix + oi] === newLines[prefix + ni]) {
          lines.push(new LexiDiffLine('equal', prefix + oi + 1, prefix + ni + 1, oldLines[prefix + oi]));
          oi += 1;
          ni += 1;
          continue;
        }
        const matches = anchorMap.get(oldLines[prefix + oi]);
        let nextMatch = -1;
        if (matches) {
          for (let k = 0; k < matches.length; k++) {
            if (matches[k] >= ni && matches[k] - ni <= 64) {
              nextMatch = matches[k];
              break;
            }
          }
        }
        if (nextMatch >= 0) {
          while (ni < nextMatch) {
            lines.push(new LexiDiffLine('add', 0, prefix + ni + 1, newLines[prefix + ni]));
            ni += 1;
          }
        } else {
          lines.push(new LexiDiffLine('remove', prefix + oi + 1, 0, oldLines[prefix + oi]));
          oi += 1;
        }
      }
      while (oi < midOldCount) {
        lines.push(new LexiDiffLine('remove', prefix + oi + 1, 0, oldLines[prefix + oi]));
        oi += 1;
      }
      while (ni < midNewCount) {
        lines.push(new LexiDiffLine('add', 0, prefix + ni + 1, newLines[prefix + ni]));
        ni += 1;
      }
    }

    for (let s = suffix - 1; s >= 0; s--) {
      const oldIdx = n - 1 - s;
      const newIdx = m - 1 - s;
      lines.push(new LexiDiffLine('equal', oldIdx + 1, newIdx + 1, oldLines[oldIdx]));
    }
    return lines;
  }

  static reasonLabel(reason: string): string {
    if (reason === 'manual') { return '手动快照'; }
    if (reason === 'restore-backup') { return '恢复前自动备份'; }
    if (reason === 'conflict-backup') { return '并发冲突备份'; }
    if (reason === 'crash-recovery') { return '异常退出恢复'; }
    return '自动保存';
  }

  static formatBytes(bytes: number): string {
    if (bytes < 1024) { return `${bytes} B`; }
    if (bytes < 1024 * 1024) { return `${(bytes / 1024).toFixed(1)} KB`; }
    return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
  }
}

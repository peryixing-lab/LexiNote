import { GraphNode, LexiLinkCandidate, MindMapDoc, NoteItem, NoteLink } from './LexiModels';
import { MarkdownEngine } from './MarkdownEngine';

export class RelatedContent {
  id: string = '';
  title: string = '';
  snippet: string = '';
  kind: string = 'note';
  reason: string = '';
}

class LexiScoredLinkCandidate {
  item: LexiLinkCandidate = new LexiLinkCandidate();
  score: number = 0;
  updatedAt: number = 0;
}

/** Human-readable, deduplicated relations, independent of graph display filters. */
export class LexiRelations {
  static counts(contents: GraphNode[], maps: MindMapDoc[], links: NoteLink[]): Map<string, number> {
    const neighbours = new Map<string, Set<string>>();
    for (const content of contents) { neighbours.set(content.id, new Set<string>()); }
    const connect = (source: string, target: string): void => {
      if (source === target) { return; }
      const a = neighbours.get(source);
      const b = neighbours.get(target);
      if (a && b) { a.add(target); b.add(source); }
    };
    for (const link of links) { connect(link.sourceId, link.targetId); }
    for (const map of maps) {
      if (map.trashedAt > 0) { continue; }
      for (const node of map.nodes) { connect(`map:${map.id}`, node.noteRefId); }
    }
    const result = new Map<string, number>();
    neighbours.forEach((ids: Set<string>, id: string): void => { result.set(id, ids.size); });
    return result;
  }

  static contents(notes: NoteItem[], maps: MindMapDoc[]): GraphNode[] {
    const result: GraphNode[] = [];
    for (const note of notes) {
      if (note.trashedAt > 0) { continue; }
      const node = new GraphNode();
      node.id = note.id;
      node.label = MarkdownEngine.displayTitle(note);
      node.snippet = MarkdownEngine.extractSnippet(note);
      result.push(node);
    }
    for (const map of maps) {
      if (map.trashedAt > 0) { continue; }
      const node = new GraphNode();
      node.id = `map:${map.id}`;
      node.label = map.title || '未命名导图';
      node.kind = 'mindmap';
      node.snippet = '思维导图';
      result.push(node);
    }
    return result;
  }

  static connected(focusId: string, contents: GraphNode[], maps: MindMapDoc[], links: NoteLink[]): RelatedContent[] {
    const reasons = new Map<string, string>();
    for (const link of links) {
      if (!link.targetId || link.sourceId === link.targetId) { continue; }
      if (link.sourceId === focusId) { reasons.set(link.targetId, '这篇笔记引用了它'); }
      if (link.targetId === focusId) {
        reasons.set(link.sourceId, reasons.has(link.sourceId) ? '两篇笔记互相引用' : '它引用了这篇笔记');
      }
    }
    // Reciprocal links can arrive in either order.
    for (const link of links) {
      if (link.sourceId === focusId && links.some((other: NoteLink): boolean =>
        other.sourceId === link.targetId && other.targetId === focusId)) {
        reasons.set(link.targetId, '两篇笔记互相引用');
      }
    }
    for (const map of maps) {
      if (map.trashedAt > 0) { continue; }
      for (const node of map.nodes) {
        if (!node.noteRefId) { continue; }
        if (focusId === `map:${map.id}`) { reasons.set(node.noteRefId, '导图中的笔记引用'); }
        if (focusId === node.noteRefId) { reasons.set(`map:${map.id}`, '这张导图引用了它'); }
      }
    }
    const result: RelatedContent[] = [];
    for (const content of contents) {
      const reason = reasons.get(content.id);
      if (!reason || content.id === focusId) { continue; }
      const related = new RelatedContent();
      related.id = content.id;
      related.title = content.label;
      related.snippet = content.snippet;
      related.kind = content.kind;
      related.reason = reason;
      result.push(related);
    }
    return result;
  }

  static connectedNoteIds(links: NoteLink[], maps: MindMapDoc[] = [], includeMaps: boolean = false): Set<string> {
    const ids = new Set<string>();
    for (const link of links) {
      if (link.targetId && link.sourceId && link.sourceId !== link.targetId) {
        ids.add(link.sourceId);
        ids.add(link.targetId);
      }
    }
    if (includeMaps) {
      for (const map of maps) {
        if (map.trashedAt > 0) { continue; }
        for (const node of map.nodes) {
          if (node.noteRefId) { ids.add(node.noteRefId); }
        }
      }
    }
    return ids;
  }

  static unconnectedNotes(
    notes: NoteItem[],
    links: NoteLink[],
    maps: MindMapDoc[] = [],
    includeMaps: boolean = false
  ): NoteItem[] {
    const connected = LexiRelations.connectedNoteIds(links, maps, includeMaps);
    return notes.filter((note: NoteItem): boolean => note.trashedAt === 0 && !connected.has(note.id));
  }

  static isNoteUnconnected(noteId: string, links: NoteLink[]): boolean {
    if (!noteId) { return false; }
    return !links.some((link: NoteLink): boolean =>
      !!link.targetId && link.sourceId !== link.targetId && (link.sourceId === noteId || link.targetId === noteId));
  }

  static suggestLinkCandidates(
    note: NoteItem,
    notes: NoteItem[],
    links: NoteLink[],
    limit: number = 4
  ): LexiLinkCandidate[] {
    const active = notes.filter((n: NoteItem): boolean =>
      n.trashedAt === 0 && n.id !== note.id && n.vaultId === note.vaultId);
    const linked = new Set<string>();
    for (const link of links) {
      if (link.sourceId === note.id && link.targetId) { linked.add(link.targetId); }
      if (link.targetId === note.id && link.sourceId) { linked.add(link.sourceId); }
    }
    const sourceTitleLower = (note.title.trim() || MarkdownEngine.displayTitle(note)).toLowerCase();
    const sourceBodyLower = note.content.toLowerCase();
    const sourceTags = new Set<string>(note.tags.map((t: string): string => t.trim().toLowerCase()));
    const scored: LexiScoredLinkCandidate[] = [];
    for (const other of active) {
      if (linked.has(other.id)) { continue; }
      const otherTitle = MarkdownEngine.displayTitle(other);
      const otherTitleLower = otherTitle.toLowerCase();
      let score = 0;
      let reason = '';
      if (otherTitle.length >= 2 && sourceBodyLower.includes(otherTitleLower)) {
        score += 5;
        reason = '正文中提及此笔记';
      } else if (sourceTitleLower.length >= 2 && other.content.toLowerCase().includes(sourceTitleLower)) {
        score += 4;
        reason = '对方正文中提及本笔记';
      }
      for (const rawTag of other.tags) {
        const lowerTag = rawTag.trim().toLowerCase();
        if (lowerTag && sourceTags.has(lowerTag)) {
          score += 3;
          if (!reason) { reason = `共同标签 #${rawTag}`; }
          break;
        }
      }
      if (other.notebook && note.notebook && other.notebook === note.notebook) {
        score += 1;
        if (!reason) { reason = `同在「${other.notebook}」`; }
      }
      if (score === 0) { continue; }
      const candidate = new LexiLinkCandidate();
      candidate.noteId = other.id;
      candidate.title = otherTitle;
      candidate.notebook = other.notebook || '笔记';
      candidate.reason = reason;
      const entry = new LexiScoredLinkCandidate();
      entry.item = candidate;
      entry.score = score;
      entry.updatedAt = other.updatedAt;
      scored.push(entry);
    }
    scored.sort((a: LexiScoredLinkCandidate, b: LexiScoredLinkCandidate): number =>
      b.score !== a.score ? b.score - a.score : b.updatedAt - a.updatedAt);
    return scored.slice(0, limit).map((s: LexiScoredLinkCandidate): LexiLinkCandidate => s.item);
  }
}

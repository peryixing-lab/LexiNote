import type { NoteItem, NoteSortMode } from '../../shared/types';

/**
 * Shared search grammar ported from core/LexiSearch.ets: plain text, tag:,
 * type:, notebook:, path:, [property]: and -exclusion tokens; quoted phrases.
 */

export interface SearchTerm {
  field: string;
  text: string;
  excluded: boolean;
}

export function parseQuery(query: string): SearchTerm[] {
  const tokens = query.match(/(?:[^\s"']+|"[^"]*"|'[^']*')+/g) ?? [];
  const result: SearchTerm[] = [];
  for (const token of tokens) {
    let text = token;
    let excluded = false;
    if (text.startsWith('-') && text.length > 1) {
      excluded = true;
      text = text.substring(1);
    }
    let field = '';
    const colon = text.indexOf(':');
    if (colon > 0) {
      const candidate = text.substring(0, colon).toLowerCase();
      if (['tag', 'type', 'notebook', 'path'].includes(candidate) || /^\[[^\]]+\]$/.test(candidate)) {
        field = candidate;
        text = text.substring(colon + 1);
      }
    }
    const cleaned = text.replace(/^["']|["']$/g, '').toLowerCase();
    if (cleaned) result.push({ field, text: cleaned, excluded });
  }
  return result;
}

export function matchesSearch(note: NoteItem, query: string): boolean {
  const haystack = `${note.title}\n${note.content}\n${note.notebook}\n${note.tags.join(' ')}`.toLowerCase();
  for (const term of parseQuery(query)) {
    let found = false;
    if (term.field === 'tag') {
      const tag = term.text.replace(/^#/, '');
      found = note.tags.some((item) => item.toLowerCase() === tag || item.toLowerCase().startsWith(`${tag}/`));
    } else if (term.field === 'type') {
      found = note.noteType.toLowerCase() === term.text;
    } else if (term.field === 'notebook') {
      found = note.notebook.toLowerCase().includes(term.text);
    } else if (term.field === 'path') {
      found = note.path.toLowerCase().includes(term.text);
    } else if (term.field.startsWith('[')) {
      const key = term.field.substring(1, term.field.length - 1);
      found = note.properties.some(
        (prop) => prop.key.toLowerCase() === key && prop.value.toLowerCase().includes(term.text)
      );
    } else {
      found = haystack.includes(term.text);
    }
    if (term.excluded ? found : !found) return false;
  }
  return true;
}

/** Lower is better; a subsequence also accepts initials typed in order. */
export function rankTitle(title: string, query: string): number {
  const needle = query.trim().toLowerCase();
  const text = title.toLowerCase();
  if (!needle) return 0;
  if (text === needle) return 0;
  const offset = text.indexOf(needle);
  if (offset >= 0) return 1 + offset;
  let cursor = 0;
  let gaps = 0;
  for (let i = 0; i < needle.length; i++) {
    const next = text.indexOf(needle[i], cursor);
    if (next < 0) return -1;
    gaps += next - cursor;
    cursor = next + 1;
  }
  return 100 + gaps;
}

/** Extract positive query phrases/keywords used to highlight and anchor search results. */
export function extractHighlightTerms(query: string): string[] {
  const terms: string[] = [];
  for (const term of parseQuery(query)) {
    if (term.excluded || term.field === 'type') continue;
    const raw = term.field === 'tag' ? term.text.replace(/^#/, '') : term.text;
    const clean = raw.trim().toLowerCase();
    if (clean.length > 0 && !terms.includes(clean)) terms.push(clean);
  }
  terms.sort((a, b) => b.length - a.length);
  return terms;
}

export function highlightSegments(text: string, query: string): { text: string; hit: boolean }[] {
  if (!text) return [];
  const terms = extractHighlightTerms(query);
  if (terms.length === 0) return [{ text, hit: false }];
  const lower = text.toLowerCase();
  const segments: { text: string; hit: boolean }[] = [];
  let cursor = 0;
  while (cursor < text.length) {
    let bestStart = -1;
    let bestLength = 0;
    for (const term of terms) {
      const idx = lower.indexOf(term, cursor);
      if (idx >= 0 && (bestStart < 0 || idx < bestStart || (idx === bestStart && term.length > bestLength))) {
        bestStart = idx;
        bestLength = term.length;
      }
    }
    if (bestStart < 0) {
      segments.push({ text: text.slice(cursor), hit: false });
      break;
    }
    if (bestStart > cursor) segments.push({ text: text.slice(cursor, bestStart), hit: false });
    segments.push({ text: text.slice(bestStart, bestStart + bestLength), hit: true });
    cursor = bestStart + bestLength;
  }
  return segments;
}

export function noteAccessTimestamp(note: NoteItem): number {
  return note.lastOpenedAt && note.lastOpenedAt > 0 ? note.lastOpenedAt : note.updatedAt;
}

export function sortNotes(
  notes: NoteItem[],
  mode: NoteSortMode = 'updated',
  options?: { pinnedFirst?: boolean }
): NoteItem[] {
  const pinnedFirst = options?.pinnedFirst ?? false;
  return notes.slice().sort((a, b) => {
    if (pinnedFirst && a.pinned !== b.pinned) return Number(b.pinned) - Number(a.pinned);
    if (mode === 'accessed') {
      const diff = noteAccessTimestamp(b) - noteAccessTimestamp(a);
      if (diff !== 0) return diff;
      return b.updatedAt - a.updatedAt;
    }
    if (mode === 'created') return b.createdAt - a.createdAt;
    if (mode === 'title') {
      return (a.title || a.id).localeCompare(b.title || b.id, 'zh-Hans-CN');
    }
    return b.updatedAt - a.updatedAt;
  });
}

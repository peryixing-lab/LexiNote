import type { NoteItem } from '../../shared/types';

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

export function highlightSegments(text: string, query: string): { text: string; hit: boolean }[] {
  const needle = query.trim();
  if (!needle) return [{ text, hit: false }];
  const segments: { text: string; hit: boolean }[] = [];
  const lower = text.toLowerCase();
  const lowerNeedle = needle.toLowerCase();
  let cursor = 0;
  let index = lower.indexOf(lowerNeedle);
  while (index >= 0) {
    if (index > cursor) segments.push({ text: text.slice(cursor, index), hit: false });
    segments.push({ text: text.slice(index, index + needle.length), hit: true });
    cursor = index + needle.length;
    index = lower.indexOf(lowerNeedle, cursor);
  }
  if (cursor < text.length) segments.push({ text: text.slice(cursor), hit: false });
  return segments;
}

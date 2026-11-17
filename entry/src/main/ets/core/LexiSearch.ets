import { LexiHighlightSpan, NoteItem, NoteProperty } from './LexiModels';

export class LexiSearchTerm {
  field: string = '';
  text: string = '';
  excluded: boolean = false;
}

/** Shared search grammar for the library, desktop tree and quick switcher. */
export class LexiSearch {
  static parse(query: string): LexiSearchTerm[] {
    const tokens = query.match(/(?:[^\s"']+|"[^"]*"|'[^']*')+/g) ?? [];
    const result: LexiSearchTerm[] = [];
    for (const token of tokens) {
      const term = new LexiSearchTerm();
      let text = token;
      if (text.startsWith('-') && text.length > 1) { term.excluded = true; text = text.substring(1); }
      const colon = text.indexOf(':');
      if (colon > 0) {
        const field = text.substring(0, colon).toLowerCase();
        if (['tag', 'type', 'notebook', 'path'].includes(field) || /^\[[^\]]+\]$/.test(field)) {
          term.field = field; text = text.substring(colon + 1);
        }
      }
      term.text = text.replace(/^["']|["']$/g, '').toLowerCase();
      if (term.text) { result.push(term); }
    }
    return result;
  }

  static matches(note: NoteItem, query: string): boolean {
    const haystack = `${note.title}\n${note.content}\n${note.notebook}\n${note.tags.join(' ')}`.toLowerCase();
    for (const term of LexiSearch.parse(query)) {
      let found = false;
      if (term.field === 'tag') {
        const tag = term.text.replace(/^#/, '');
        found = note.tags.some((item: string): boolean => item.toLowerCase() === tag || item.toLowerCase().startsWith(`${tag}/`));
      } else if (term.field === 'type') {
        found = note.noteType.toLowerCase() === term.text;
      } else if (term.field === 'notebook') {
        found = note.notebook.toLowerCase().includes(term.text);
      } else if (term.field === 'path') {
        found = note.path.toLowerCase().includes(term.text);
      } else if (term.field.startsWith('[')) {
        const key = term.field.substring(1, term.field.length - 1);
        found = note.properties.some((prop: NoteProperty): boolean =>
          prop.key.toLowerCase() === key && prop.propValue.toLowerCase().includes(term.text));
      } else { found = haystack.includes(term.text); }
      if (term.excluded ? found : !found) { return false; }
    }
    return true;
  }

  /** Lower is better; a subsequence also accepts initials typed in order. */
  static rank(title: string, query: string): number {
    const needle = query.trim().toLowerCase();
    const text = title.toLowerCase();
    if (!needle) { return 0; }
    if (text === needle) { return 0; }
    const offset = text.indexOf(needle);
    if (offset >= 0) { return 1 + offset; }
    let cursor = 0;
    let gaps = 0;
    for (let i = 0; i < needle.length; i++) {
      const next = text.indexOf(needle[i], cursor);
      if (next < 0) { return -1; }
      gaps += next - cursor; cursor = next + 1;
    }
    return 100 + gaps;
  }

  static highlightTerms(query: string): string[] {
    const terms: string[] = [];
    for (const term of LexiSearch.parse(query)) {
      if (term.excluded || term.field === 'type') { continue; }
      const raw = term.field === 'tag' ? term.text.replace(/^#/, '') : term.text;
      const clean = raw.trim().toLowerCase();
      if (clean.length > 0 && !terms.includes(clean)) {
        terms.push(clean);
      }
    }
    terms.sort((a: string, b: string): number => b.length - a.length);
    return terms;
  }

  static highlightSegments(text: string, query: string): LexiHighlightSpan[] {
    if (!text) { return []; }
    const terms = LexiSearch.highlightTerms(query);
    if (!terms.length) {
      const whole = new LexiHighlightSpan();
      whole.id = 'hl-0';
      whole.text = text;
      whole.hit = false;
      return [whole];
    }
    const lower = text.toLowerCase();
    const result: LexiHighlightSpan[] = [];
    let cursor = 0;
    let index = 0;
    while (cursor < text.length) {
      let bestStart = -1;
      let bestLength = 0;
      for (const term of terms) {
        const found = lower.indexOf(term, cursor);
        if (found >= 0 && (bestStart < 0 || found < bestStart || (found === bestStart && term.length > bestLength))) {
          bestStart = found;
          bestLength = term.length;
        }
      }
      if (bestStart < 0 || bestLength <= 0) {
        const tail = new LexiHighlightSpan();
        tail.id = `hl-${index++}`;
        tail.text = text.substring(cursor);
        tail.hit = false;
        result.push(tail);
        break;
      }
      if (bestStart > cursor) {
        const before = new LexiHighlightSpan();
        before.id = `hl-${index++}`;
        before.text = text.substring(cursor, bestStart);
        before.hit = false;
        result.push(before);
      }
      const match = new LexiHighlightSpan();
      match.id = `hl-${index++}`;
      match.text = text.substring(bestStart, bestStart + bestLength);
      match.hit = true;
      result.push(match);
      cursor = bestStart + bestLength;
    }
    return result;
  }

  static sortNotes(notes: NoteItem[], sortMode: string): NoteItem[] {
    const sorted = notes.slice();
    if (sortMode === 'title') {
      sorted.sort((a: NoteItem, b: NoteItem): number => {
        const titleFor = (item: NoteItem): string => {
          if (item.title.trim().length > 0) { return item.title.trim(); }
          const first = item.content.split('\n')
            .map((line: string): string => line.replace(/^[#>*\-\s]+/, '').trim())
            .find((line: string): boolean => line.length > 0);
          return first ? first.slice(0, 28) : '未命名速记';
        };
        return titleFor(a).localeCompare(titleFor(b));
      });
    } else if (sortMode === 'created') {
      sorted.sort((a: NoteItem, b: NoteItem): number => b.createdAt - a.createdAt);
    } else if (sortMode === 'accessed') {
      sorted.sort((a: NoteItem, b: NoteItem): number => {
        const aAccess = a.lastOpenedAt || 0;
        const bAccess = b.lastOpenedAt || 0;
        if (aAccess !== bAccess) {
          return bAccess - aAccess;
        }
        if (a.pinned !== b.pinned) {
          return a.pinned ? -1 : 1;
        }
        return b.updatedAt - a.updatedAt;
      });
    } else {
      sorted.sort((a: NoteItem, b: NoteItem): number => {
        if (a.pinned !== b.pinned) {
          return a.pinned ? -1 : 1;
        }
        return b.updatedAt - a.updatedAt;
      });
    }
    return sorted;
  }
}

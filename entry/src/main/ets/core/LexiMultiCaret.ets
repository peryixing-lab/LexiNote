export class LexiMultiCaretEdit {
  content: string = '';
  carets: number[] = [];
}
export class LexiMultiCaretRange { start: number = 0; end: number = 0; }
export class LexiMultiCaret {
  static insert(text: string, positions: number[], snippet: string): LexiMultiCaretEdit {
    const sorted = Array.from(new Set<number>(positions)).sort((a: number, b: number): number => a - b);
    const result = new LexiMultiCaretEdit(); result.content = text;
    for (let i = sorted.length - 1; i >= 0; i--) { const at = sorted[i]; result.content = result.content.substring(0, at) + snippet + result.content.substring(at); }
    result.carets = positions.map((position: number): number => position + sorted.filter((other: number): boolean => other <= position).length * snippet.length);
    return result;
  }
  static remove(text: string, positions: number[], backward: boolean, length: number): LexiMultiCaretEdit {
    const ranges: LexiMultiCaretRange[] = positions.map((position: number): LexiMultiCaretRange => {
      const range = new LexiMultiCaretRange();
      range.start = backward ? Math.max(0, position - length) : position;
      range.end = backward ? position : Math.min(text.length, position + length);
      if (range.start > 0 && text.charCodeAt(range.start) >= 0xDC00 && text.charCodeAt(range.start) <= 0xDFFF) { range.start--; }
      if (range.end < text.length && text.charCodeAt(range.end) >= 0xDC00 && text.charCodeAt(range.end) <= 0xDFFF) { range.end++; }
      return range;
    }).sort((a: LexiMultiCaretRange, b: LexiMultiCaretRange): number => a.start - b.start);
    const merged: LexiMultiCaretRange[] = [];
    for (const range of ranges) {
      const last = merged.length ? merged[merged.length - 1] : undefined;
      if (last && range.start <= last.end) { last.end = Math.max(last.end, range.end); } else { merged.push(range); }
    }
    const result = new LexiMultiCaretEdit(); result.content = text;
    for (let i = merged.length - 1; i >= 0; i--) { result.content = result.content.substring(0, merged[i].start) + result.content.substring(merged[i].end); }
    result.carets = positions.map((position: number): number => {
      let removed = 0;
      for (const range of merged) { removed += Math.max(0, Math.min(position, range.end) - range.start); }
      return position - removed;
    });
    return result;
  }
}

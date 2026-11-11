/** Pure Markdown edits shared by keyboard commands and native editor tools. */
export class LexiEditingResult {
  content: string = '';
  start: number = 0;
  end: number = 0;
}

export class LexiEditingActions {
  static replace(text: string, start: number, end: number, replacement: string): LexiEditingResult {
    const result = new LexiEditingResult();
    result.content = text.substring(0, start) + replacement + text.substring(end);
    result.start = start; result.end = start + replacement.length;
    return result;
  }

  static wrap(text: string, start: number, end: number, left: string, right: string): LexiEditingResult {
    const selected = text.substring(start, end);
    if (selected.startsWith(left) && selected.endsWith(right) && selected.length >= left.length + right.length) {
      return LexiEditingActions.replace(text, start, end, selected.substring(left.length, selected.length - right.length));
    }
    if (text.substring(Math.max(0, start - left.length), start) === left && text.substring(end, end + right.length) === right) {
      return LexiEditingActions.replace(text, start - left.length, end + right.length, selected);
    }
    const result = LexiEditingActions.replace(text, start, end, left + selected + right);
    result.start += left.length; result.end -= right.length;
    return result;
  }

  static cells(line: string): string[] {
    let source = line.trim();
    if (source.startsWith('|')) { source = source.substring(1); }
    if (source.endsWith('|') && !source.endsWith('\\|')) { source = source.substring(0, source.length - 1); }
    const cells: string[] = []; let cell = ''; let escaped = false; let ticks = false;
    for (const character of source) {
      if (character === '|' && !escaped && !ticks) { cells.push(cell.trim()); cell = ''; }
      else { cell += character; }
      if (character === '`' && !escaped) { ticks = !ticks; }
      if (character === '\\' && !escaped) { escaped = true; } else { escaped = false; }
    }
    cells.push(cell.trim()); return cells;
  }

  static table(text: string, caret: number, action: string): LexiEditingResult {
    const lines = text.split('\n'); const rowIndex = text.substring(0, caret).split('\n').length - 1;
    let first = rowIndex; let last = rowIndex;
    let fenced = false;
    for (let i = 0; i <= rowIndex; i++) { if (/^\s*(```|~~~)/.test(lines[i])) { fenced = !fenced; } }
    if (fenced || !lines[rowIndex].includes('|')) { throw new Error('请将光标放在 Markdown 表格中'); }
    while (first > 0 && lines[first - 1].includes('|') && lines[first - 1].trim()) { first--; }
    while (last + 1 < lines.length && lines[last + 1].includes('|') && lines[last + 1].trim()) { last++; }
    if (last - first < 1 || !/^\s*\|?\s*:?-{3,}/.test(lines[first + 1])) { throw new Error('当前区域不是 Markdown 表格'); }
    const rows: string[][] = lines.slice(first, last + 1).map((line: string): string[] => LexiEditingActions.cells(line));
    const count = rows[0].length;
    for (const row of rows) { while (row.length < count) { row.push(''); } }
    const lineStart = lines.slice(0, rowIndex).reduce((total: number, line: string): number => total + line.length + 1, 0);
    const prefix = lines[rowIndex].substring(0, Math.max(0, caret - lineStart));
    let separators = 0; let escaped = false; let ticks = false;
    for (const character of prefix) {
      if (character === '|' && !escaped && !ticks) { separators++; }
      if (character === '`' && !escaped) { ticks = !ticks; }
      if (character === '\\' && !escaped) { escaped = true; } else { escaped = false; }
    }
    const column = Math.min(count - 1, Math.max(0, separators - (lines[rowIndex].trimStart().startsWith('|') ? 1 : 0)));
    const selectedRow = rowIndex - first;
    if (action === 'row-delete' || action === 'row-copy' || action === 'row-up' || action === 'row-down') {
      if (selectedRow < 2) { throw new Error('请将光标放在表格数据行中'); }
      if (action === 'row-delete') { rows.splice(selectedRow, 1); }
      if (action === 'row-copy') { rows.splice(selectedRow + 1, 0, rows[selectedRow].slice()); }
      const next = action === 'row-up' ? selectedRow - 1 : selectedRow + 1;
      if ((action === 'row-up' || action === 'row-down') && next >= 2 && next < rows.length) {
        const saved = rows[selectedRow]; rows[selectedRow] = rows[next]; rows[next] = saved;
      }
    } else if (action === 'row-before' || action === 'row-after') {
      const empty: string[] = []; for (let i = 0; i < count; i++) { empty.push(''); }
      rows.splice(Math.max(2, selectedRow + (action === 'row-after' ? 1 : 0)), 0, empty);
    } else if (action.startsWith('align-')) {
      rows[1][column] = action === 'align-center' ? ':---:' : action === 'align-right' ? '---:' : ':---';
    } else {
      if (action === 'col-delete' && count <= 1) { throw new Error('表格至少保留一列'); }
      for (let i = 0; i < rows.length; i++) {
        const row = rows[i];
        if (action === 'col-delete') { row.splice(column, 1); }
        else if (action === 'col-copy') { row.splice(column + 1, 0, row[column]); }
        else if (action === 'col-before' || action === 'col-after') { row.splice(column + (action === 'col-after' ? 1 : 0), 0, i === 1 ? '---' : ''); }
        else if (action === 'col-left' || action === 'col-right') {
          const next = column + (action === 'col-left' ? -1 : 1);
          if (next >= 0 && next < count) { const saved = row[column]; row[column] = row[next]; row[next] = saved; }
        }
      }
    }
    const replacement = rows.map((row: string[]): string => '| ' + row.join(' | ') + ' |').join('\n');
    const start = lines.slice(0, first).reduce((total: number, line: string): number => total + line.length + 1, 0);
    const end = start + lines.slice(first, last + 1).join('\n').length;
    const result = LexiEditingActions.replace(text, start, end, replacement);
    result.start = start; result.end = start;
    return result;
  }

  static apply(text: string, start: number, end: number, action: string): LexiEditingResult {
    start = Math.max(0, Math.min(text.length, start)); end = Math.max(start, Math.min(text.length, end));
    if (action.startsWith('table-')) { return LexiEditingActions.table(text, start, action.substring(6)); }
    if (action === 'bold') { return LexiEditingActions.wrap(text, start, end, '**', '**'); }
    if (action === 'italic') { return LexiEditingActions.wrap(text, start, end, '*', '*'); }
    if (action === 'strike') { return LexiEditingActions.wrap(text, start, end, '~~', '~~'); }
    if (action.startsWith('highlight-')) {
      const color = action.substring(10);
      if (!['red', 'orange', 'yellow', 'green', 'blue', 'purple'].includes(color)) { throw new Error('未知高亮颜色'); }
      return LexiEditingActions.wrap(text, start, end, '<mark data-color="' + color + '">', '</mark>');
    }
    if (action === 'highlight') { return LexiEditingActions.wrap(text, start, end, '==', '=='); }
    if (action === 'inline-code') { return LexiEditingActions.wrap(text, start, end, '`', '`'); }
    if (action === 'inline-math') { return LexiEditingActions.wrap(text, start, end, '$', '$'); }
    if (action === 'comment') { return LexiEditingActions.wrap(text, start, end, '%%', '%%'); }
    if (action === 'code') { return LexiEditingActions.wrap(text, start, end, '\n```\n', '\n```\n'); }
    if (action === 'formula') { return LexiEditingActions.wrap(text, start, end, '\n$$\n', '\n$$\n'); }
    if (action === 'link') { return LexiEditingActions.wrap(text, start, end, '[', '](https://)'); }
    if (action === 'wiki') { return LexiEditingActions.wrap(text, start, end, '[[', ']]'); }
    if (action === 'embed') { return LexiEditingActions.wrap(text, start, end, '![[', ']]'); }
    if (action === 'hr') { return LexiEditingActions.replace(text, start, end, '\n\n---\n\n'); }
    if (action === 'table') { return LexiEditingActions.replace(text, start, end, '\n| 名称 | 内容 |\n| --- | --- |\n|  |  |\n'); }
    if (action === 'footnote') { return LexiEditingActions.replace(text, start, end, '[^' + String(Date.now()) + ']: ' + text.substring(start, end)); }
    if (action === 'callout') { return LexiEditingActions.wrap(text, start, end, '\n> [!NOTE]\n> ', '\n'); }
    if (action === 'clear-format') {
      return LexiEditingActions.replace(text, start, end, text.substring(start, end).replace(/(\*\*|~~|==|`)/g, '').replace(/\*([^*\n]+)\*/g, '$1'));
    }
    const first = text.lastIndexOf('\n', Math.max(0, start - 1)) + 1;
    const after = text.indexOf('\n', end); const last = after < 0 ? text.length : after;
    const selectedLines = text.substring(first, last).split('\n');
    if (action === 'line-up' && first > 0) {
      const previous = text.lastIndexOf('\n', Math.max(0, first - 2)) + 1;
      return LexiEditingActions.replace(text, previous, last, selectedLines.join('\n') + '\n' + text.substring(previous, first - 1));
    }
    if (action === 'line-down' && last < text.length) {
      const next = text.indexOf('\n', last + 1); const nextEnd = next < 0 ? text.length : next;
      return LexiEditingActions.replace(text, first, nextEnd, text.substring(last + 1, nextEnd) + '\n' + selectedLines.join('\n'));
    }
    if (action === 'delete-paragraph') { return LexiEditingActions.replace(text, first, Math.min(text.length, last + 1), ''); }
    const lines = selectedLines.map((line: string, index: number): string => {
      if (/^h[1-6]$/.test(action)) { return '#'.repeat(Number(action.substring(1))) + ' ' + line.replace(/^#{1,6}\s+/, ''); }
      if (action === 'heading-clear') { return line.replace(/^#{1,6}\s+/, ''); }
      if (action === 'indent') { return '  ' + line; }
      if (action === 'outdent') { return line.replace(/^( {1,4}|\t)/, ''); }
      if (action === 'bullet') { return /^\s*[-*+] /.test(line) ? line.replace(/^(\s*)[-*+] /, '$1') : '- ' + line; }
      if (action === 'ordered') { return /^\s*\d+\. /.test(line) ? line.replace(/^(\s*)\d+\. /, '$1') : String(index + 1) + '. ' + line; }
      if (action === 'quote') { return line.startsWith('> ') ? line.substring(2) : '> ' + line; }
      if (action === 'todo') {
        if (/^\s*[-*] \[[ xX]\]/.test(line)) { return line.replace(/\[([ xX])\]/, line.includes('[ ]') ? '[x]' : '[ ]'); }
        return '- [ ] ' + line.replace(/^\s*[-*+] /, '');
      }
      return line;
    });
    return LexiEditingActions.replace(text, first, last, lines.join('\n'));
  }
}

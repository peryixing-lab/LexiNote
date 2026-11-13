import type { MindMapDoc, MindMapNode, NoteItem, NoteProperty, OutlineHeading } from '../../shared/types';
import { displayBlock, inlineTokens } from './math';

/**
 * Markdown engine ported from the HarmonyOS app (core/MarkdownEngine.ets and
 * core/LexiFrontmatter.ets). The same block grammar is used by the editor,
 * the reading view, the outline, backlinks, cards and the mind-map converter,
 * so every surface agrees about what a note contains.
 */

export type BlockKind =
  | 'h1' | 'h2' | 'h3' | 'paragraph' | 'bullet' | 'ordered' | 'todo'
  | 'quote' | 'callout' | 'code' | 'formula' | 'table' | 'hr' | 'image' | 'embed';

export interface MarkdownBlock {
  id: string;
  kind: BlockKind;
  text: string;
  meta: string;
  lineIndex: number;
  checked?: boolean;
}

export type SpanKind = 'text' | 'code' | 'link' | 'url' | 'bold' | 'italic' | 'strike' | 'highlight' | 'math' | 'math-display';

export interface InlineSpan {
  id: string;
  text: string;
  kind: SpanKind;
  target?: string;
}

export interface MarkdownTable {
  rows: string[][];
  alignments: string[];
}

export interface FrontmatterResult {
  hasFrontmatter: boolean;
  body: string;
  bodyLineOffset: number;
  tags: string[];
  properties: NoteProperty[];
  rawHeader: string;
}

export interface WikiLink {
  targetText: string;
  anchor: string;
  displayText: string;
}

export interface ExtractedLink {
  sourceId: string;
  sourceTitle: string;
  targetId: string;
  targetTitle: string;
  anchor: string;
  displayText: string;
}

export interface UnlinkedMention {
  sourceId: string;
  sourceTitle: string;
  targetId: string;
  targetTitle: string;
  snippet: string;
}

const FRONTMATTER_PATTERN = /^\uFEFF?---[ \t]*\r?\n([\s\S]*?)\r?\n---[ \t]*(?=\r?\n|$)/;

function scalar(raw: string): string {
  let text = raw.trim();
  let quote = '';
  for (let index = 0; index < text.length; index++) {
    const char = text[index];
    if ((char === '"' || char === "'") && (index === 0 || text[index - 1] !== '\\')) {
      if (!quote) quote = char;
      else if (quote === char) quote = '';
    }
    if (char === '#' && !quote && (index === 0 || /\s/.test(text[index - 1]))) {
      text = text.slice(0, index).trim();
      break;
    }
  }
  if (text.startsWith('"') && text.endsWith('"')) {
    try {
      return JSON.parse(text) as string;
    } catch {
      return text;
    }
  }
  if (text.startsWith("'") && text.endsWith("'")) return text.slice(1, -1).replace(/''/g, "'");
  return text === 'null' || text === '~' ? '' : text;
}

interface YamlField {
  key: string;
  text: string;
  parsed: string;
  supported: boolean;
}

function yamlFields(header: string): YamlField[] {
  const result: YamlField[] = [];
  for (const line of header.split('\n')) {
    const matched = /^("(?:[^"\\]|\\.)+"|'(?:[^']|'')+'|[^\s:#][^:]*):(?:\s+(.*)|\s*)$/.exec(line);
    if (!matched) {
      if (result.length > 0) result[result.length - 1].text += `\n${line}`;
      else result.push({ key: '', text: line, parsed: '', supported: false });
      continue;
    }
    const field: YamlField = { key: scalar(matched[1]), text: line, parsed: scalar(matched[2] || ''), supported: true };
    field.supported = !/^[>|{&*!]/.test((matched[2] || '').trim());
    result.push(field);
  }
  for (const field of result) {
    const rows = field.text.split('\n').slice(1).filter((line) => !!line.trim() && !line.trim().startsWith('#'));
    if (rows.length > 0) {
      if (rows.every((line) => /^\s+-\s+/.test(line))) {
        field.parsed = JSON.stringify(rows.map((line) => scalar(line.replace(/^\s+-\s+/, ''))));
        field.supported = true;
      } else {
        field.supported = false;
      }
    }
  }
  return result;
}

function yamlList(raw: string): string[] {
  const text = raw.trim();
  if (text.startsWith('[') && text.endsWith(']')) {
    const items: string[] = [];
    let part = '';
    let quote = '';
    for (let i = 1; i < text.length - 1; i++) {
      const char = text[i];
      if ((char === '"' || char === "'") && (i === 0 || text[i - 1] !== '\\')) {
        if (!quote) quote = char;
        else if (quote === char) quote = '';
      }
      if (char === ',' && !quote) {
        items.push(scalar(part));
        part = '';
      } else {
        part += char;
      }
    }
    if (part.trim()) items.push(scalar(part));
    return items;
  }
  return text ? [scalar(text)] : [];
}

export function parseFrontmatter(raw: string): FrontmatterResult {
  const result: FrontmatterResult = {
    hasFrontmatter: false,
    body: raw,
    bodyLineOffset: 0,
    tags: [],
    properties: [],
    rawHeader: ''
  };
  const normalized = raw.replace(/^\uFEFF/, '').replace(/\r\n/g, '\n');
  if (!normalized.startsWith('---\n')) return result;
  const lines = normalized.split('\n');
  let end = -1;
  for (let i = 1; i < lines.length; i++) {
    if (lines[i] === '---' || lines[i] === '...') {
      end = i;
      break;
    }
  }
  if (end < 0) return result;
  result.hasFrontmatter = true;
  result.bodyLineOffset = end + 1;
  result.rawHeader = lines.slice(1, end).join('\n');
  result.body = lines.slice(end + 1).join('\n');
  for (const field of yamlFields(result.rawHeader)) {
    if (field.key === 'tags' || field.key === 'tag') {
      for (const tag of yamlList(field.parsed)) {
        const cleaned = tag.replace(/^#/, '').trim();
        if (cleaned && !result.tags.includes(cleaned)) result.tags.push(cleaned);
      }
    } else if (field.key && field.supported) {
      result.properties.push({ key: field.key, value: field.parsed });
    }
  }
  return result;
}

/** Rewrites frontmatter for exported files without touching note bodies. */
export function serializeFrontmatter(note: NoteItem): string {
  const parsed = parseFrontmatter(note.content);
  if (!parsed.hasFrontmatter && note.tags.length === 0 && note.properties.length === 0) return note.content;
  const output: string[] = [];
  const used: string[] = [];
  const tags = note.tags.filter((tag) => !!tag.trim()).map((tag) => tag.replace(/^#/, '').trim());
  for (const field of yamlFields(parsed.rawHeader)) {
    if (field.key === 'tag' || field.key === 'tags') {
      if (!used.includes('tags')) {
        output.push(`tags: ${JSON.stringify(tags)}`);
        used.push('tags');
      }
    } else if (!field.key || !field.supported) {
      if (field.text.trim()) output.push(field.text);
      if (field.key) used.push(field.key);
    } else {
      const prop = note.properties.find((item) => item.key === field.key);
      if (prop) {
        output.push(
          prop.value === field.parsed
            ? field.text
            : `${JSON.stringify(prop.key)}: ${JSON.stringify(prop.value)}`
        );
        used.push(prop.key);
      }
    }
  }
  if (tags.length > 0 && !used.includes('tags')) output.push(`tags: ${JSON.stringify(tags)}`);
  for (const prop of note.properties) {
    if (prop.key.trim() && prop.key !== 'tag' && prop.key !== 'tags' && !used.includes(prop.key)) {
      output.push(`${JSON.stringify(prop.key)}: ${JSON.stringify(prop.value)}`);
      used.push(prop.key);
    }
  }
  return `---\n${output.join('\n')}\n---\n${parsed.body}`;
}

export function extractInlineTags(markdown: string): string[] {
  const tags: string[] = [];
  let fence = '';
  for (const line of markdown.split('\n')) {
    if (fence) {
      if (new RegExp(`^\\s*${fence.charAt(0)}{${fence.length},}\\s*$`).test(line)) fence = '';
      continue;
    }
    const fenceMatch = /^\s*(`{3,}|~{3,})/.exec(line);
    if (fenceMatch) {
      fence = fenceMatch[1];
      continue;
    }
    const regex = /(?:^|\s)#([\u4e00-\u9fa5A-Za-z0-9_/-]{1,28})/g;
    let match: RegExpExecArray | null = regex.exec(line);
    while (match !== null) {
      const tag = match[1].trim();
      if (tag.length > 0 && !tags.includes(tag)) tags.push(tag);
      match = regex.exec(line);
    }
  }
  return tags;
}

export function displayTitle(note: Pick<NoteItem, 'title' | 'content'>): string {
  if (note.title.trim().length > 0) return note.title.trim();
  const firstLine = parseFrontmatter(note.content).body
    .split('\n')
    .map((line) => line.replace(/^[#>*\-\s]+/, '').trim())
    .find((line) => line.length > 0);
  if (firstLine) return firstLine.slice(0, 28);
  return '未命名速记';
}

export function splitTableRow(line: string): string[] {
  let raw = line.trim();
  if (raw.startsWith('|')) raw = raw.substring(1);
  if (raw.endsWith('|') && !raw.endsWith('\\|')) raw = raw.substring(0, raw.length - 1);
  const cells: string[] = [];
  const mathTokens = inlineTokens(raw);
  let mathIndex = 0;
  let cell = '';
  let inCode = false;
  for (let index = 0; index < raw.length; index++) {
    const character = raw[index];
    const mathToken = mathTokens[mathIndex];
    if (mathToken && index === mathToken.start) {
      cell += raw.substring(mathToken.start, mathToken.end);
      index = mathToken.end - 1;
      mathIndex++;
    } else if (character === '\\' && raw[index + 1] === '|') {
      cell += '|';
      index++;
    } else if (character === '`') {
      inCode = !inCode;
      cell += character;
    } else if (character === '|' && !inCode) {
      cells.push(cell.trim());
      cell = '';
    } else {
      cell += character;
    }
  }
  cells.push(cell.trim());
  return cells;
}

export function tableData(block: MarkdownBlock): MarkdownTable {
  try {
    return JSON.parse(block.meta) as MarkdownTable;
  } catch {
    return { rows: [], alignments: [] };
  }
}

// ---------------------------------------------------------------------------
// Inline spans

function appendMathSpans(spans: InlineSpan[], text: string, offset: number, kind: SpanKind): void {
  let cursor = 0;
  for (const token of inlineTokens(text)) {
    if (token.start > cursor) {
      spans.push({ id: `text-${offset + cursor}`, kind, text: text.substring(cursor, token.start) });
    }
    spans.push({
      id: `math-${offset + token.start}`,
      text: token.text,
      kind: token.displayMode ? 'math-display' : 'math'
    });
    cursor = token.end;
  }
  if (cursor < text.length) {
    spans.push({ id: `text-${offset + cursor}`, kind, text: text.substring(cursor) });
  }
}

export function inlineSpans(text: string): InlineSpan[] {
  const spans: InlineSpan[] = [];
  let protectedText = '';
  let protectedCursor = 0;
  for (const token of inlineTokens(text)) {
    protectedText += text.substring(protectedCursor, token.start) + '\uFFFC'.repeat(token.end - token.start);
    protectedCursor = token.end;
  }
  protectedText += text.substring(protectedCursor);
  const pattern =
    /`([^`]+)`|\[\[([^[\]]+)\]\]|\[([^\]]+)\]\(([^\s)]+)(?:\s+"[^"]*")?\)|\*\*([^*]+)\*\*|__([^_]+)__|==([^=]+)==|~~([^~]+)~~|\*([^*\n]+)\*|_([^_\n]+)_|<mark data-color="(red|orange|yellow|green|blue|purple)">([^<]+)<\/mark>/g;
  let cursor = 0;
  let match: RegExpExecArray | null = pattern.exec(protectedText);
  while (match !== null) {
    if (match.index > cursor) {
      appendMathSpans(spans, text.substring(cursor, match.index), cursor, 'text');
    }
    const raw = text.substring(match.index, match.index + match[0].length);
    const segment: InlineSpan = { id: `mark-${match.index}`, kind: 'text', text: '' };
    let contentOffset = match.index + 1;
    if (match[1]) {
      segment.kind = 'code';
      segment.text = raw.substring(1, raw.length - 1);
    } else if (match[2]) {
      const parts = raw.substring(2, raw.length - 2).split('|');
      segment.kind = 'link';
      segment.target = parts[0].trim();
      segment.text = parts.length > 1 ? parts.slice(1).join('|').trim() : segment.target;
    } else if (match[3]) {
      segment.kind = 'url';
      segment.text = raw.substring(1, 1 + match[3].length);
      segment.target = match[4];
    } else if (match[5] || match[6]) {
      segment.kind = 'bold';
      segment.text = raw.substring(2, raw.length - 2);
      contentOffset++;
    } else if (match[7]) {
      segment.kind = 'highlight';
      segment.text = raw.substring(2, raw.length - 2);
      contentOffset++;
    } else if (match[8]) {
      segment.kind = 'strike';
      segment.text = raw.substring(2, raw.length - 2);
      contentOffset++;
    } else if (match[11]) {
      segment.kind = 'highlight';
      segment.target = match[11];
      segment.text = match[12];
      contentOffset = match.index + raw.indexOf('>') + 1;
    } else {
      segment.kind = 'italic';
      segment.text = raw.substring(1, raw.length - 1);
    }
    if (
      segment.kind !== 'code' &&
      segment.kind !== 'link' &&
      segment.kind !== 'url' &&
      inlineTokens(segment.text).length > 0
    ) {
      appendMathSpans(spans, segment.text, contentOffset, segment.kind);
    } else {
      spans.push(segment);
    }
    cursor = match.index + match[0].length;
    match = pattern.exec(protectedText);
  }
  if (cursor < text.length) appendMathSpans(spans, text.substring(cursor), cursor, 'text');
  return spans;
}

// ---------------------------------------------------------------------------
// Blocks

export function parseBlocks(markdown: string): MarkdownBlock[] {
  const blocks: MarkdownBlock[] = [];
  const lines = markdown.split('\n');
  let i = parseFrontmatter(markdown).bodyLineOffset;
  while (i < lines.length) {
    const raw = lines[i];
    const trimmed = raw.trim();
    if (trimmed.length === 0) {
      i++;
      continue;
    }
    const fenceOpen = /^(`{3,}|~{3,})(.*)$/.exec(trimmed);
    if (fenceOpen) {
      const fence = fenceOpen[1];
      const lang = fenceOpen[2].trim().split(/\s+/)[0] || 'code';
      const codeLines: string[] = [];
      const startLine = i;
      i++;
      const closePattern = new RegExp(`^${fence.charAt(0)}{${fence.length},}\\s*$`);
      while (i < lines.length && !closePattern.test(lines[i].trim())) {
        codeLines.push(lines[i]);
        i++;
      }
      i++;
      const fenceText = codeLines.join('\n');
      const langLower = lang.toLowerCase();
      const isMathFence = langLower === 'math' || langLower === 'katex';
      if (isMathFence) {
        blocks.push({
          id: `block-${startLine}`,
          kind: 'formula',
          text: fenceText.trim().replace(/^(?:\$\$|\\\[)\s*([\s\S]*?)\s*(?:\$\$|\\\])$/, '$1').trim(),
          meta: '',
          lineIndex: startLine
        });
      } else {
        blocks.push({
          id: `block-${startLine}`,
          kind: 'code',
          text: fenceText,
          meta: lang,
          lineIndex: startLine
        });
      }
      continue;
    }
    const formula = displayBlock(lines, i);
    if (formula) {
      const startLine = i;
      i = formula.endLine + 1;
      blocks.push({ id: `block-${startLine}`, kind: 'formula', text: formula.text, meta: '', lineIndex: startLine });
      continue;
    }
    const block: MarkdownBlock = { id: `block-${i}`, kind: 'paragraph', text: '', meta: '', lineIndex: i };
    const heading = /^(#{1,6})\s+(.+?)(?:\s+#+\s*)?$/.exec(trimmed);
    const ordered = /^(\d{1,9})[.)]\s+(.+)$/.exec(trimmed);
    const image = /^!\[([^\]]*)\]\((<[^>]+>|[^)]+?)(?:\s+"[^"]*")?\)$/.exec(trimmed);
    const embed = /^!\[\[([^[\]]+)\]\]$/.exec(trimmed);
    const separator = i + 1 < lines.length ? splitTableRow(lines[i + 1]) : [];
    if (
      trimmed.includes('|') &&
      separator.length > 0 &&
      separator.every((cell) => /^:?-{3,}:?$/.test(cell))
    ) {
      const table: MarkdownTable = { rows: [], alignments: [] };
      const headers = splitTableRow(trimmed);
      if (headers.length === separator.length) {
        table.rows.push(headers);
        table.alignments = separator.map((cell) =>
          cell.startsWith(':') && cell.endsWith(':') ? 'center' : cell.endsWith(':') ? 'right' : 'left'
        );
        i += 2;
        while (i < lines.length && lines[i].trim().includes('|') && lines[i].trim().length > 0) {
          const cells = splitTableRow(lines[i]);
          while (cells.length < headers.length) cells.push('');
          table.rows.push(cells.slice(0, headers.length));
          i++;
        }
        blocks.push({
          id: `block-${block.lineIndex}`,
          kind: 'table',
          text: headers.join(' | '),
          meta: JSON.stringify(table),
          lineIndex: block.lineIndex
        });
        continue;
      }
    }
    if (heading) {
      block.kind = `h${Math.min(3, heading[1].length)}` as BlockKind;
      block.meta = String(heading[1].length);
      block.text = heading[2].trim();
    } else if (/^(?:\*\s*){3,}$|^(?:-\s*){3,}$|^(?:_\s*){3,}$/.test(trimmed)) {
      block.kind = 'hr';
    } else if (image) {
      block.kind = 'image';
      block.text = image[1];
      block.meta = image[2];
    } else if (embed) {
      block.kind = /\.(?:png|jpe?g|gif|webp|svg|bmp|avif)$/i.test(embed[1].split('|')[0].trim()) ? 'image' : 'embed';
      block.meta = embed[1].split('|')[0].trim();
      block.text = embed[1].split('|').slice(1).join('|').trim() || block.meta;
    } else if (ordered) {
      block.kind = 'ordered';
      block.meta = ordered[1];
      block.text = ordered[2];
    } else if (/^[-*+]\s+\[[xX]\](?:\s|$)/.test(trimmed)) {
      block.kind = 'todo';
      block.checked = true;
      block.text = trimmed.replace(/^[-*+]\s+\[[xX]\]\s*/, '');
    } else if (/^[-*+]\s+\[ \](?:\s|$)/.test(trimmed)) {
      block.kind = 'todo';
      block.checked = false;
      block.text = trimmed.replace(/^[-*+]\s+\[ \]\s*/, '');
    } else if (trimmed.startsWith('- ') || trimmed.startsWith('* ') || trimmed.startsWith('+ ')) {
      block.kind = 'bullet';
      block.text = trimmed.substring(2).trim();
    } else if (trimmed.startsWith('> [!')) {
      block.kind = 'callout';
      const calloutMatch = /^>\s*\[!([A-Za-z]+)\]/.exec(trimmed);
      block.meta = calloutMatch ? calloutMatch[1].toUpperCase() : 'NOTE';
      const bodyLines: string[] = [trimmed.replace(/^>\s*\[![A-Za-z]+\]\s*/, '')];
      while (i + 1 < lines.length && lines[i + 1].trim().startsWith('>')) {
        i++;
        bodyLines.push(lines[i].trim().replace(/^>\s?/, ''));
      }
      block.text = bodyLines.filter((s) => s.length > 0).join('\n');
    } else if (trimmed === '>' || trimmed.startsWith('> ')) {
      block.kind = 'quote';
      const quoteLines: string[] = [trimmed.replace(/^>\s?/, '')];
      while (
        i + 1 < lines.length &&
        (lines[i + 1].trim() === '>' || lines[i + 1].trim().startsWith('> ')) &&
        !lines[i + 1].trim().startsWith('> [!')
      ) {
        i++;
        quoteLines.push(lines[i].trim().replace(/^>\s?/, ''));
      }
      block.text = quoteLines.filter((s) => s.length > 0).join('\n');
    } else {
      block.kind = 'paragraph';
      block.text = trimmed;
    }
    blocks.push(block);
    i++;
  }
  return blocks;
}

export function extractOutline(markdown: string): OutlineHeading[] {
  const headings: OutlineHeading[] = [];
  const lines = markdown.split('\n');
  const firstBodyLine = parseFrontmatter(markdown).bodyLineOffset;
  let fence = '';
  for (let i = firstBodyLine; i < lines.length; i++) {
    const line = lines[i].trim();
    if (fence) {
      if (new RegExp(`^${fence.charAt(0)}{${fence.length},}\\s*$`).test(line)) fence = '';
      continue;
    }
    const fenceMatch = /^(`{3,}|~{3,})/.exec(line);
    if (fenceMatch) {
      fence = fenceMatch[1];
      continue;
    }
    const match = /^(#{1,6})\s+(.+?)(?:\s+#+\s*)?$/.exec(line);
    if (match) {
      headings.push({ id: `h-${i}`, level: match[1].length, title: match[2].trim(), lineIndex: i });
    }
  }
  return headings;
}

export function extractWikiLinks(markdown: string): WikiLink[] {
  const results: WikiLink[] = [];
  const regex = /\[\[([^[\]]+)\]\]/g;
  let match: RegExpExecArray | null = regex.exec(markdown);
  while (match !== null) {
    const inner = match[1].trim();
    if (inner.length > 0) {
      const pipeParts = inner.split('|');
      const left = pipeParts[0].trim();
      const display = pipeParts.length > 1 ? pipeParts.slice(1).join('|').trim() : left;
      const hashParts = left.split('#');
      const target = hashParts[0].trim();
      const anchor = hashParts.length > 1 ? hashParts.slice(1).join('#').trim() : '';
      if (target.length > 0) results.push({ targetText: target, anchor, displayText: display });
    }
    match = regex.exec(markdown);
  }
  return results;
}

export function buildNoteLinks(notes: NoteItem[]): ExtractedLink[] {
  const activeNotes = notes.filter((n) => n.trashedAt === 0);
  const links: ExtractedLink[] = [];
  for (const source of activeNotes) {
    for (const raw of extractWikiLinks(source.content)) {
      const target = activeNotes.find(
        (candidate) =>
          candidate.vaultId === source.vaultId &&
          (candidate.id === raw.targetText ||
            displayTitle(candidate).trim().toLowerCase() === raw.targetText.toLowerCase())
      );
      const link: ExtractedLink = {
        sourceId: source.id,
        sourceTitle: displayTitle(source),
        targetId: target ? target.id : '',
        targetTitle: target ? displayTitle(target) : raw.targetText,
        anchor: raw.anchor,
        displayText: raw.displayText
      };
      const duplicate = links.some(
        (existing) =>
          existing.sourceId === link.sourceId &&
          existing.targetTitle === link.targetTitle &&
          existing.anchor === link.anchor
      );
      if (!duplicate) links.push(link);
    }
  }
  return links;
}

export function findUnlinkedMentions(notes: NoteItem[], links: ExtractedLink[]): UnlinkedMention[] {
  const active = notes.filter((n) => n.trashedAt === 0 && n.title.trim().length >= 2);
  const mentions: UnlinkedMention[] = [];
  for (const target of active) {
    const targetTitle = target.title.trim();
    for (const source of active) {
      if (source.id === target.id || source.vaultId !== target.vaultId) continue;
      const alreadyLinked = links.some(
        (l) => l.sourceId === source.id && (l.targetId === target.id || l.targetTitle === targetTitle)
      );
      if (alreadyLinked) continue;
      const idx = source.content.indexOf(targetTitle);
      if (idx >= 0) {
        const start = Math.max(0, idx - 16);
        const end = Math.min(source.content.length, idx + targetTitle.length + 24);
        mentions.push({
          sourceId: source.id,
          sourceTitle: displayTitle(source),
          targetId: target.id,
          targetTitle,
          snippet: source.content.substring(start, end).replace(/\n/g, ' ')
        });
        if (mentions.length >= 16) return mentions;
      }
    }
  }
  return mentions;
}

export function renameLinksInMarkdown(content: string, oldTitle: string, newTitle: string): string {
  const cleanOld = oldTitle.trim();
  const cleanNew = newTitle.trim();
  if (!cleanOld || !cleanNew || cleanOld === cleanNew) return content;
  return content.replace(/\[\[([^[\]]+)\]\]/g, (_full, inner: string) => {
    const pipeParts = inner.split('|');
    const left = pipeParts[0].trim();
    const hashParts = left.split('#');
    if (hashParts[0].trim().toLowerCase() !== cleanOld.toLowerCase()) return `[[${inner}]]`;
    const anchorSuffix = hashParts.length > 1 ? `#${hashParts.slice(1).join('#')}` : '';
    const displaySuffix = pipeParts.length > 1 ? `|${pipeParts.slice(1).join('|')}` : '';
    return `[[${cleanNew}${anchorSuffix}${displaySuffix}]]`;
  });
}

export function extractEmbeddedSection(markdown: string, anchor = ''): string {
  const parsed = parseFrontmatter(markdown);
  if (!anchor.trim()) return parsed.body.trim().slice(0, 800);
  const headings = extractOutline(markdown);
  const normalized = anchor.trim().toLowerCase().replace(/\s+/g, '-');
  const heading = headings.find((candidate) => candidate.title.trim().toLowerCase().replace(/\s+/g, '-') === normalized);
  if (!heading) return '';
  const next = headings.find((candidate) => candidate.lineIndex > heading.lineIndex && candidate.level <= heading.level);
  return markdown
    .split('\n')
    .slice(heading.lineIndex + 1, next ? next.lineIndex : undefined)
    .join('\n')
    .trim()
    .slice(0, 800);
}

/** Card excerpt built from the same parser the editor uses. */
export function extractSnippet(note: NoteItem, query = ''): string {
  const segments: string[] = [];
  for (const block of parseBlocks(note.content)) {
    if (block.kind === 'hr') continue;
    let text = block.text;
    if (block.kind === 'table') {
      text = tableData(block).rows.slice(0, 3).map((row) => row.join(' · ')).join('；');
    } else if (block.kind === 'todo') text = `${block.checked ? '☑' : '☐'} ${text}`;
    else if (block.kind === 'bullet') text = `• ${text}`;
    else if (block.kind === 'ordered') text = `${block.meta}. ${text}`;
    else if (block.kind === 'image') text = block.text || '图片';
    else if (block.kind === 'embed') text = `引用：${block.text || block.meta}`;
    else if (block.kind === 'formula') text = '数学公式';
    text = text.replace(/\s+/g, ' ').trim();
    if (!text) continue;
    segments.push(text);
    if (!query.trim() && segments.join(' ').length >= 128) break;
  }
  const plain = segments.join(' ');
  if (!plain) return '点击继续记录内容…';
  const q = query.trim().toLowerCase();
  const match = q ? plain.toLowerCase().indexOf(q) : -1;
  const start = match >= 0 ? Math.max(0, match - 18) : 0;
  const end = Math.min(plain.length, match >= 0 ? match + q.length + 42 : 86);
  return `${start > 0 ? '…' : ''}${plain.slice(start, end)}${end < plain.length ? '…' : ''}`;
}

// ---------------------------------------------------------------------------
// Mind map layout (ported from MarkdownEngine.computeMindMapLayout)

export function computeMindMapLayout(doc: MindMapDoc): MindMapNode[] {
  const nodes = doc.nodes.map((node) => ({ ...node }));
  const root = nodes.find((n) => n.id === doc.rootNodeId) || nodes[0];
  if (!root) return [];
  const visible: MindMapNode[] = [];
  const childrenOf = (parentId: string): MindMapNode[] =>
    nodes.filter((n) => n.parentId === parentId).sort((a, b) => a.order - b.order);

  const measureLeaves = (node: MindMapNode): number => {
    if (node.collapsed) return 1;
    const ch = childrenOf(node.id);
    if (ch.length === 0) return 1;
    let sum = 0;
    for (const child of ch) sum += measureLeaves(child);
    return Math.max(1, sum);
  };

  const applyOffsets = (): void => {
    for (const node of visible) {
      node.x += Number.isFinite(node.offsetX) ? node.offsetX : 0;
      node.y += Number.isFinite(node.offsetY) ? node.offsetY : 0;
    }
  };

  if (doc.layoutKind === 'org') {
    const hStep = 166;
    const vStep = 92;
    const placeOrg = (node: MindMapNode, level: number, startLeaf: number): number => {
      const span = measureLeaves(node);
      node.level = level;
      node.boxWidth = Math.min(184, Math.max(116, node.text.length * 14 + 34));
      node.boxHeight = node.note.length > 0 || node.noteRefId.length > 0 ? 54 : 42;
      node.x = 80 + (startLeaf + span / 2) * hStep;
      node.y = 76 + level * vStep;
      visible.push(node);
      if (!node.collapsed) {
        let cursor = startLeaf;
        for (const child of childrenOf(node.id)) cursor += placeOrg(child, level + 1, cursor);
      }
      return span;
    };
    placeOrg(root, 0, 0);
    applyOffsets();
    return visible;
  }

  if (doc.layoutKind === 'balanced') {
    const topChildren = childrenOf(root.id);
    const rightGroup: MindMapNode[] = [];
    const leftGroup: MindMapNode[] = [];
    topChildren.forEach((child, index) => (index % 2 === 0 ? rightGroup : leftGroup).push(child));
    const vGap = 68;
    const hGap = 205;
    const rightLeaves = rightGroup.reduce((sum, node) => sum + measureLeaves(node), 0);
    const leftLeaves = leftGroup.reduce((sum, node) => sum + measureLeaves(node), 0);
    const totalLeaves = Math.max(3, Math.max(rightLeaves, leftLeaves));
    const centerY = Math.max(210, (totalLeaves * vGap) / 2 + 48);
    const centerX = 480;

    root.level = 0;
    root.boxWidth = Math.min(196, Math.max(132, root.text.length * 15 + 36));
    root.boxHeight = 48;
    root.x = centerX;
    root.y = centerY;
    visible.push(root);

    if (!root.collapsed) {
      const placeSide = (node: MindMapNode, level: number, startLeaf: number, dir: number, baseTop: number): number => {
        const span = measureLeaves(node);
        node.level = level;
        node.boxWidth = Math.min(184, Math.max(114, node.text.length * 13 + 34));
        node.boxHeight = node.note.length > 0 || node.noteRefId.length > 0 ? 52 : 42;
        node.x = centerX + dir * level * hGap;
        node.y = baseTop + (startLeaf + span / 2) * vGap;
        visible.push(node);
        if (!node.collapsed) {
          let cursor = startLeaf;
          for (const child of childrenOf(node.id)) cursor += placeSide(child, level + 1, cursor, dir, baseTop);
        }
        return span;
      };
      const rightTop = centerY - (Math.max(1, rightLeaves) * vGap) / 2;
      let rCursor = 0;
      for (const node of rightGroup) rCursor += placeSide(node, 1, rCursor, 1, rightTop);
      const leftTop = centerY - (Math.max(1, leftLeaves) * vGap) / 2;
      let lCursor = 0;
      for (const node of leftGroup) lCursor += placeSide(node, 1, lCursor, -1, leftTop);
    }
    applyOffsets();
    return visible;
  }

  const vGap = 68;
  const hGap = 206;
  const placeRight = (node: MindMapNode, level: number, startLeaf: number): number => {
    const span = measureLeaves(node);
    node.level = level;
    node.boxWidth = Math.min(192, Math.max(118, node.text.length * 14 + 34));
    node.boxHeight = node.note.length > 0 || node.noteRefId.length > 0 ? 52 : 42;
    node.x = 124 + level * hGap;
    node.y = 64 + (startLeaf + span / 2) * vGap;
    visible.push(node);
    if (!node.collapsed) {
      let cursor = startLeaf;
      for (const child of childrenOf(node.id)) cursor += placeRight(child, level + 1, cursor);
    }
    return span;
  };
  placeRight(root, 0, 0);
  applyOffsets();
  return visible;
}

export function mindMapToMarkdownOutline(doc: MindMapDoc): string {
  const lines: string[] = [`# ${doc.title}`];
  const childrenOf = (parentId: string): MindMapNode[] =>
    doc.nodes.filter((n) => n.parentId === parentId).sort((a, b) => a.order - b.order);
  const walk = (node: MindMapNode, depth: number): void => {
    if (depth > 0) {
      const indent = '  '.repeat(Math.max(0, depth - 1));
      const linkSuffix = node.noteRefTitle.length > 0 ? ` → [[${node.noteRefTitle}]]` : '';
      const noteSuffix = node.note.length > 0 ? ` （${node.note}）` : '';
      lines.push(`${indent}- ${node.text}${linkSuffix}${noteSuffix}`);
    }
    for (const child of childrenOf(node.id)) walk(child, depth + 1);
  };
  const root = doc.nodes.find((n) => n.id === doc.rootNodeId) || doc.nodes[0];
  if (root) walk(root, 0);
  return lines.join('\n');
}

export function markdownToMindMapNodes(title: string, markdown: string, noteId = ''): MindMapNode[] {
  const nodes: MindMapNode[] = [];
  const colors: MindMapNode['colorTag'][] = ['purple', 'indigo', 'teal', 'amber', 'rose'];
  const base = (): Omit<MindMapNode, 'id' | 'parentId' | 'text' | 'order' | 'colorTag'> => ({
    note: '',
    noteRefId: '',
    noteRefTitle: '',
    collapsed: false,
    level: 0,
    x: 0,
    y: 0,
    boxWidth: 136,
    boxHeight: 44,
    offsetX: 0,
    offsetY: 0
  });
  const root: MindMapNode = {
    ...base(),
    id: 'root',
    parentId: '',
    text: title.trim() || '核心主题',
    noteRefId: noteId,
    noteRefTitle: title.trim(),
    order: 0,
    colorTag: 'purple'
  };
  nodes.push(root);

  let lastH1Id = 'root';
  let lastH2Id = 'root';
  let orderCounter = 1;
  for (const rawLine of markdown.split('\n')) {
    const trimmed = rawLine.trim();
    if (trimmed.length === 0 || trimmed.startsWith('```')) continue;
    const make = (parentId: string, text: string): void => {
      nodes.push({
        ...base(),
        id: `node-${orderCounter}`,
        parentId,
        text,
        order: orderCounter,
        colorTag: colors[orderCounter % colors.length]
      });
      orderCounter++;
    };
    if (trimmed.startsWith('# ')) {
      make('root', trimmed.substring(2).trim().slice(0, 32));
      lastH1Id = `node-${orderCounter - 1}`;
      lastH2Id = lastH1Id;
    } else if (trimmed.startsWith('## ')) {
      make(lastH1Id, trimmed.substring(3).trim().slice(0, 32));
      lastH2Id = `node-${orderCounter - 1}`;
    } else if (trimmed.startsWith('### ') || trimmed.startsWith('- ')) {
      const text = trimmed.startsWith('### ') ? trimmed.substring(4).trim() : trimmed.substring(2).trim();
      if (text.length > 0 && nodes.length < 48) {
        make(lastH2Id, text.replace(/^\[[ xX]\]\s*/, '').slice(0, 32));
      }
    }
  }
  if (nodes.length === 1) {
    ['核心要点', '关联知识', '行动清单'].forEach((text, index) => {
      nodes.push({
        ...base(),
        id: `node-${index + 1}`,
        parentId: 'root',
        text,
        order: index + 1,
        colorTag: colors[index % colors.length]
      });
    });
  }
  return nodes;
}

export function wordCount(text: string): number {
  const clean = text.replace(/[#>*_`~\-\[\]()]/g, ' ').trim();
  if (!clean) return 0;
  const cjk = (clean.match(/[\u4e00-\u9fff]/g) || []).length;
  const latin = clean.replace(/[\u4e00-\u9fff]/g, ' ').trim().split(/\s+/).filter(Boolean).length;
  return cjk + latin;
}

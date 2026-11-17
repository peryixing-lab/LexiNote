import type { NoteItem } from '../../shared/types';
import {
  displayTitle,
  extractEmbeddedSection,
  inlineSpans,
  parseBlocks,
  parseFrontmatter,
  tableData,
  type MarkdownBlock
} from './markdown';
import { CALLOUT_LABELS, escapeHtml, highlightCodeHtml, renderMathHtml } from './mathRender';

function renderInlineHtml(text: string, notesById: Map<string, NoteItem>, notes: NoteItem[]): string {
  const spans = inlineSpans(text);
  return spans
    .map((span) => {
      switch (span.kind) {
        case 'code':
          return `<code class="inline-code">${escapeHtml(span.text)}</code>`;
        case 'bold':
          return `<strong>${escapeHtml(span.text)}</strong>`;
        case 'italic':
          return `<em>${escapeHtml(span.text)}</em>`;
        case 'strike':
          return `<del>${escapeHtml(span.text)}</del>`;
        case 'highlight':
          return `<mark class="highlight-${escapeHtml(span.target ?? 'yellow')}">${escapeHtml(span.text)}</mark>`;
        case 'link': {
          const target = span.target ?? '';
          const internal = notes.some(
            (n) => n.id === target || displayTitle(n).trim().toLowerCase() === target.toLowerCase()
          );
          return `<span class="${internal ? 'wiki-link' : 'md-link'}">${escapeHtml(span.text)}</span>`;
        }
        case 'url':
          return `<a class="md-link" href="${escapeHtml(span.target ?? '#')}">${escapeHtml(span.text)}</a>`;
        case 'math': {
          const rendered = renderMathHtml(span.text, false);
          if (!rendered) {
            return `<code class="math-error">$${escapeHtml(span.text)}$</code>`;
          }
          return `<span class="math-inline">${rendered}</span>`;
        }
        case 'math-display': {
          const rendered = renderMathHtml(span.text, true);
          if (!rendered) {
            return `<code class="math-error">$$${escapeHtml(span.text)}$$</code>`;
          }
          return `<span class="math-display">${rendered}</span>`;
        }
        default:
          return escapeHtml(span.text);
      }
    })
    .join('');
}

function resolveImageUrl(src: string, currentNote: NoteItem): string {
  const trimmed = src.trim();
  if (!trimmed) return '';
  if (/^(https?:|data:image\/|blob:)/i.test(trimmed)) return trimmed;
  return `lexi-asset://local/?vaultId=${encodeURIComponent(currentNote.vaultId)}&notebook=${encodeURIComponent(currentNote.notebook || '默认')}&notePath=${encodeURIComponent(currentNote.path || '')}&src=${encodeURIComponent(trimmed)}`;
}

function renderBlockHtml(
  block: MarkdownBlock,
  currentNote: NoteItem,
  notes: NoteItem[],
  notesById: Map<string, NoteItem>
): string {
  const inline = (value: string) => renderInlineHtml(value, notesById, notes);
  switch (block.kind) {
    case 'h1':
    case 'h2':
    case 'h3': {
      const level = Math.min(6, Math.max(1, Number(block.meta) || Number(block.kind.substring(1)) || 1));
      return `<h${level} class="md-block md-heading md-h${level}">${inline(block.text)}</h${level}>`;
    }
    case 'paragraph':
      return `<p class="md-block md-paragraph">${inline(block.text)}</p>`;
    case 'bullet':
      return `<div class="md-block md-bullet-block"><span class="md-bullet-marker">•</span><span class="md-list-text">${inline(block.text)}</span></div>`;
    case 'ordered':
      return `<div class="md-block md-ordered-block"><span class="md-bullet-marker md-ordered-marker">${escapeHtml(block.meta)}.</span><span class="md-list-text">${inline(block.text)}</span></div>`;
    case 'todo':
      return `<div class="md-block md-todo-block${block.checked ? ' is-checked' : ''}"><span class="md-checkbox">${block.checked ? '✓' : ''}</span><span class="md-list-text">${inline(block.text)}</span></div>`;
    case 'quote':
      return `<blockquote class="md-block md-quote">${inline(block.text)}</blockquote>`;
    case 'callout': {
      const meta = CALLOUT_LABELS[block.meta] ?? CALLOUT_LABELS.NOTE;
      const typeClass = escapeHtml(block.meta.toLowerCase());
      return `<div class="md-block callout callout-${typeClass}"><div class="callout-title"><span class="callout-mark">${escapeHtml(meta.mark)}</span>${escapeHtml(block.meta)}</div><div class="callout-body">${inline(block.text)}</div></div>`;
    }
    case 'code': {
      const highlighted = highlightCodeHtml(block.text, block.meta);
      const lang = escapeHtml(block.meta || 'text');
      return `<div class="md-block code-block"><div class="code-block-bar"><span>${lang}</span></div><pre><code class="hljs language-${lang}">${highlighted}</code></pre></div>`;
    }
    case 'formula': {
      const rendered = renderMathHtml(block.text, true);
      if (!rendered) {
        return `<div class="md-block md-formula"><code class="math-error">$$${escapeHtml(block.text)}$$</code></div>`;
      }
      return `<div class="md-block md-formula"><span class="math-display">${rendered}</span></div>`;
    }
    case 'hr':
      return '<hr class="md-block md-hr" />';
    case 'image': {
      const url = resolveImageUrl(block.meta || '', currentNote);
      const caption = block.text ? `<figcaption>${escapeHtml(block.text)}</figcaption>` : '';
      return url
        ? `<figure class="md-block md-image"><img src="${escapeHtml(url)}" alt="${escapeHtml(block.text || '')}" />${caption}</figure>`
        : `<div class="md-block md-image-missing">${escapeHtml(block.meta || '')}</div>`;
    }
    case 'embed': {
      const target = notesById.get(block.meta) ?? notes.find((n) => displayTitle(n) === block.meta);
      const excerpt = target ? extractEmbeddedSection(target.content, '') : '';
      const body = excerpt ? inline(excerpt.replace(/\n+/g, ' ').slice(0, 240)) : '';
      return `<div class="md-block md-embed"><div class="embed-title">${escapeHtml(block.text || block.meta)}</div>${body ? `<div class="embed-body">${body}</div>` : ''}</div>`;
    }
    case 'table': {
      const table = tableData(block);
      const header = table.rows[0] ?? [];
      const body = table.rows.slice(1);
      const ths = header
        .map((cell, idx) => `<th style="text-align:${escapeHtml(table.alignments[idx] || 'left')}">${inline(cell)}</th>`)
        .join('');
      const trs = body
        .map(
          (row) =>
            `<tr>${row
              .map((cell, idx) => `<td style="text-align:${escapeHtml(table.alignments[idx] || 'left')}">${inline(cell)}</td>`)
              .join('')}</tr>`
        )
        .join('');
      return `<div class="md-block md-table-wrap"><table class="md-table"><thead><tr>${ths}</tr></thead><tbody>${trs}</tbody></table></div>`;
    }
    default:
      return `<p class="md-block">${escapeHtml(block.text)}</p>`;
  }
}

export interface PdfExportOptions {
  language?: 'zh-Hans' | 'en';
  forBrowserHtml?: boolean;
}

const PRINT_STYLES = `
@page { size: A4; margin: 16mm 18mm; }
* { box-sizing: border-box; }
:root {
  --text: #1A1D24;
  --text-2: #586070;
  --brand: #6E44D9;
  --brand-soft: #F1ECFE;
  --border: #E5E7EE;
  --surface: #F6F7FB;
  --error: #C44D62;
}
html, body {
  margin: 0;
  padding: 0;
  background: #FFFFFF;
  color: var(--text);
  font-family: -apple-system, "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif;
  font-size: 14.5px;
  line-height: 1.75;
  -webkit-print-color-adjust: exact;
  print-color-adjust: exact;
}
.pdf-page {
  max-width: 740px;
  margin: 0 auto;
  padding: 20px 8px 32px;
}
.doc-header {
  border-bottom: 1px solid var(--border);
  padding-bottom: 14px;
  margin-bottom: 22px;
}
.doc-title {
  margin: 0 0 8px;
  font-size: 28px;
  line-height: 1.25;
  font-weight: 700;
  color: var(--text);
}
.doc-meta {
  display: flex;
  flex-wrap: wrap;
  gap: 8px 12px;
  align-items: center;
  font-size: 12px;
  color: var(--text-2);
}
.doc-badge {
  background: var(--brand-soft);
  color: var(--brand);
  padding: 2px 8px;
  border-radius: 999px;
  font-weight: 500;
}
.doc-tag {
  background: var(--surface);
  border: 1px solid var(--border);
  padding: 1px 7px;
  border-radius: 999px;
}
.markdown-body > *:first-child { margin-top: 0; }
.md-heading { font-weight: 650; line-height: 1.35; margin: 22px 0 10px; break-after: avoid; }
.md-h1 { font-size: 23px; }
.md-h2 { font-size: 19px; }
.md-h3 { font-size: 16.5px; }
.md-paragraph { margin: 0 0 11px; }
.md-bullet-block, .md-ordered-block, .md-todo-block {
  display: flex;
  align-items: baseline;
  gap: 8px;
  margin: 4px 0;
  padding-left: 4px;
}
.md-bullet-marker {
  color: var(--brand);
  font-weight: 700;
  min-width: 14px;
  flex: none;
}
.md-ordered-marker { font-weight: 600; font-size: 13px; }
.md-checkbox {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 14px;
  height: 14px;
  border-radius: 4px;
  border: 1.5px solid var(--brand);
  font-size: 10px;
  line-height: 1;
  color: #FFFFFF;
  background: transparent;
  transform: translateY(1px);
  flex: none;
}
.md-todo-block.is-checked .md-checkbox { background: var(--brand); }
.md-todo-block.is-checked .md-list-text { color: var(--text-2); text-decoration: line-through; }
.md-quote {
  margin: 12px 0;
  padding: 6px 14px;
  border-left: 3px solid var(--brand);
  color: var(--text-2);
  background: #FAF9FE;
  border-radius: 0 8px 8px 0;
}
.callout {
  margin: 14px 0;
  padding: 12px 14px;
  border-radius: 10px;
  border: 1px solid #DFD7FA;
  background: #F7F4FF;
  break-inside: avoid;
}
.callout-tip { border-color: #CBEBD8; background: #F2FBF6; }
.callout-warning, .callout-caution { border-color: #F6DFB8; background: #FFF9EF; }
.callout-important { border-color: #F2C9D2; background: #FFF4F6; }
.callout-title { display: flex; align-items: center; gap: 6px; font-weight: 650; font-size: 13px; margin-bottom: 5px; color: var(--brand); }
.callout-tip .callout-title { color: #197A4E; }
.callout-warning .callout-title, .callout-caution .callout-title { color: #B4630E; }
.callout-important .callout-title { color: #B72A48; }
.inline-code {
  font-family: "Cascadia Code", "JetBrains Mono", Consolas, monospace;
  font-size: 0.9em;
  background: #EFEBF8;
  color: #462A96;
  padding: 1px 5px;
  border-radius: 4px;
}
.code-block {
  margin: 14px 0;
  border: 1px solid var(--border);
  border-radius: 10px;
  overflow: hidden;
  background: #F8F9FC;
  break-inside: avoid;
}
.code-block-bar {
  padding: 5px 12px;
  font-size: 11px;
  color: var(--text-2);
  background: #F0F2F7;
  border-bottom: 1px solid var(--border);
  text-transform: uppercase;
  letter-spacing: 0.04em;
}
.code-block pre {
  margin: 0;
  padding: 12px 14px;
  overflow-x: auto;
  font-family: "Cascadia Code", "JetBrains Mono", Consolas, monospace;
  font-size: 12.5px;
  line-height: 1.6;
  white-space: pre-wrap;
  word-break: break-word;
}
.hljs-comment, .hljs-quote { color: #6A737D; font-style: italic; }
.hljs-keyword, .hljs-selector-tag, .hljs-subst { color: #A626A4; }
.hljs-number, .hljs-literal, .hljs-variable, .hljs-template-variable { color: #986801; }
.hljs-string, .hljs-doctag { color: #50A14F; }
.hljs-title, .hljs-section, .hljs-selector-id { color: #4078F2; font-weight: 600; }
.hljs-type, .hljs-class .hljs-title { color: #C18401; }
.hljs-tag, .hljs-name, .hljs-attribute { color: #E45649; }
.hljs-built_in, .hljs-builtin-name { color: #0184BC; }
.math-inline { display: inline-block; vertical-align: middle; }
.md-formula { margin: 14px 0; text-align: center; break-inside: avoid; overflow-x: auto; }
.math-display { display: block; text-align: center; }
.math-error { color: var(--error); background: #FFF2F4; padding: 2px 6px; border-radius: 4px; }
.md-hr { border: none; border-top: 1px solid var(--border); margin: 18px 0; }
.md-image { margin: 14px 0; text-align: center; break-inside: avoid; }
.md-image img { max-width: 100%; max-height: 480px; border-radius: 8px; border: 1px solid var(--border); }
.md-image figcaption { font-size: 12px; color: var(--text-2); margin-top: 6px; }
.md-embed { margin: 12px 0; padding: 10px 14px; border: 1px solid var(--border); border-radius: 8px; background: var(--surface); break-inside: avoid; }
.embed-title { font-weight: 600; margin-bottom: 4px; color: var(--brand); }
.md-table-wrap { margin: 14px 0; overflow-x: auto; break-inside: avoid; }
.md-table { width: 100%; border-collapse: collapse; font-size: 13px; }
.md-table th, .md-table td { border: 1px solid var(--border); padding: 7px 10px; }
.md-table th { background: var(--surface); font-weight: 600; }
.wiki-link { color: var(--brand); text-decoration: underline; text-decoration-style: dashed; }
.md-link { color: var(--brand); text-decoration: underline; }
mark { padding: 0 3px; border-radius: 3px; background: #FFF3A8; }
`;

export function buildPdfExportHtml(
  note: NoteItem,
  notes: NoteItem[],
  options: PdfExportOptions = {}
): string {
  const title = displayTitle(note);
  const { body } = parseFrontmatter(note.content);
  const blocks = parseBlocks(body);
  const notesById = new Map(notes.map((n) => [n.id, n]));
  const bodyHtml = blocks.map((block) => renderBlockHtml(block, note, notes, notesById)).join('\n');
  const locale = options.language === 'en' ? 'en-US' : 'zh-CN';
  const updated = note.updatedAt ? new Date(note.updatedAt).toLocaleString(locale) : '';
  const tagsHtml = (note.tags ?? [])
    .filter((tag) => tag.trim().length > 0)
    .map((tag) => `<span class="doc-tag">#${escapeHtml(tag)}</span>`)
    .join('');

  const katexLink = options.forBrowserHtml
    ? ''
    : '<link rel="stylesheet" href="lexi-asset://katex/katex.min.css">';

  return `<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>${escapeHtml(title)}</title>
${katexLink}
<style>${PRINT_STYLES}</style>
</head>
<body>
  <article class="pdf-page">
    <header class="doc-header">
      <h1 class="doc-title">${escapeHtml(title)}</h1>
      <div class="doc-meta">
        ${note.notebook ? `<span class="doc-badge">${escapeHtml(note.notebook)}</span>` : ''}
        ${updated ? `<span>${escapeHtml(updated)}</span>` : ''}
        ${tagsHtml}
      </div>
    </header>
    <main class="markdown-body">${bodyHtml}</main>
  </article>
</body>
</html>`;
}

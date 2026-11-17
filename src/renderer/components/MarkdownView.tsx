import React, { useMemo, useState } from 'react';
import 'katex/dist/katex.min.css';
import type { NoteItem } from '../../shared/types';
import {
  MarkdownBlock,
  InlineSpan,
  inlineSpans,
  parseBlocks,
  tableData,
  displayTitle,
  extractEmbeddedSection
} from '../core/markdown';
import { CALLOUT_LABELS, highlightCodeHtml, renderMathHtml } from '../core/mathRender';
import { CheckGlyph } from './Symbols';
import { LinkPreviewPopover } from './LinkPreviewPopover';
import { tr } from '../core/i18n';

export const renderMath = renderMathHtml;

export function MathSpan({ tex, display }: { tex: string; display: boolean }): JSX.Element {
  const html = useMemo(() => renderMath(tex, display), [tex, display]);
  if (!html) {
    return (
      <code className="math-error" title="公式无法排版，保留 LaTeX 原文">
        {display ? `$$${tex}$$` : `$${tex}$`}
      </code>
    );
  }
  return (
    <span
      className={display ? 'math-display' : 'math-inline'}
      dangerouslySetInnerHTML={{ __html: html }}
    />
  );
}

function CodeBlock({ code, language }: { code: string; language: string }): JSX.Element {
  const [copied, setCopied] = useState(false);
  const rendered = useMemo(() => highlightCodeHtml(code, language), [code, language]);

  const copy = (): void => {
    void navigator.clipboard.writeText(code);
    setCopied(true);
    window.setTimeout(() => setCopied(false), 1400);
  };

  return (
    <div className="code-block">
      <div className="code-block-bar">
        <span>{language || 'text'}</span>
        <button type="button" className="code-copy" onClick={copy}>
          {copied ? tr('已复制') : tr('复制')}
        </button>
      </div>
      <pre>
        <code className={`hljs language-${language}`} dangerouslySetInnerHTML={{ __html: rendered }} />
      </pre>
    </div>
  );
}

interface InlineProps {
  text: string;
  notes?: NoteItem[];
  onOpenTarget?: (target: string) => void;
}

export function InlineContent({ text, notes = [], onOpenTarget }: InlineProps): JSX.Element {
  const spans = useMemo(() => inlineSpans(text), [text]);
  return (
    <>
      {spans.map((span: InlineSpan) => {
        switch (span.kind) {
          case 'code':
            return (
              <code key={span.id} className="inline-code">
                {span.text}
              </code>
            );
          case 'bold':
            return <strong key={span.id}>{span.text}</strong>;
          case 'italic':
            return <em key={span.id}>{span.text}</em>;
          case 'strike':
            return <del key={span.id}>{span.text}</del>;
          case 'highlight':
            return (
              <mark key={span.id} className={`highlight-${span.target ?? 'yellow'}`}>
                {span.text}
              </mark>
            );
          case 'link': {
            const target = span.target ?? '';
            const baseTarget = (target.split('#')[0] ?? target).trim().toLowerCase();
            const internal = notes.some(
              (note) =>
                note.trashedAt === 0 &&
                (note.id === target ||
                  note.id.toLowerCase() === baseTarget ||
                  displayTitle(note).trim().toLowerCase() === baseTarget)
            );
            return (
              <LinkPreviewPopover key={span.id} target={target} onOpenTarget={onOpenTarget}>
                <a
                  className={internal ? 'wiki-link' : 'wiki-link missing'}
                  href="#"
                  onClick={(event) => {
                    event.preventDefault();
                    event.stopPropagation();
                    onOpenTarget?.(target);
                  }}
                >
                  {span.text}
                </a>
              </LinkPreviewPopover>
            );
          }
          case 'url':
            return (
              <a
                key={span.id}
                className="md-link"
                href={span.target}
                onClick={(event) => {
                  event.preventDefault();
                  event.stopPropagation();
                  if (span.target) void window.lexi?.openExternal(span.target);
                }}
              >
                {span.text}
              </a>
            );
          case 'math':
            return <MathSpan key={span.id} tex={span.text} display={false} />;
          case 'math-display':
            return <MathSpan key={span.id} tex={span.text} display />;
          default:
            return <React.Fragment key={span.id}>{span.text}</React.Fragment>;
        }
      })}
    </>
  );
}

interface MarkdownBlocksProps {
  content: string;
  notes?: NoteItem[];
  currentNote?: NoteItem;
  onOpenTarget?: (target: string) => void;
  onToggleTodo?: (lineIndex: number) => void;
  anchorPrefix?: string;
  compact?: boolean;
}

/** Read-only renderer shared by reading mode, previews and exported surfaces. */
export function MarkdownBlocks({
  content,
  notes = [],
  currentNote,
  onOpenTarget,
  onToggleTodo,
  anchorPrefix = 'md'
}: MarkdownBlocksProps): JSX.Element {
  const blocks = useMemo(() => parseBlocks(content), [content]);
  const notesById = useMemo(() => new Map(notes.map((note) => [note.id, note])), [notes]);

  return (
    <div className="markdown-body">
      {blocks.map((block) => (
        <BlockView
          key={`${anchorPrefix}-${block.id}`}
          block={block}
          notes={notes}
          notesById={notesById}
          currentNote={currentNote}
          onOpenTarget={onOpenTarget}
          onToggleTodo={onToggleTodo}
          readOnly
        />
      ))}
    </div>
  );
}

interface BlockViewProps {
  block: MarkdownBlock;
  notes: NoteItem[];
  notesById: Map<string, NoteItem>;
  currentNote?: NoteItem;
  onOpenTarget?: (target: string) => void;
  onToggleTodo?: (lineIndex: number) => void;
  readOnly?: boolean;
  onActivate?: () => void;
  active?: boolean;
}

export function BlockView({
  block,
  notes,
  notesById,
  currentNote,
  onOpenTarget,
  onToggleTodo,
  readOnly = true,
  onActivate
}: BlockViewProps): JSX.Element {
  const lineAttr = { 'data-line': block.lineIndex } as React.HTMLAttributes<HTMLElement>;
  const commonProps = {
    ...lineAttr,
    className: `md-block md-${block.kind}${readOnly ? '' : ' md-editable'}`,
    onClick: readOnly
      ? undefined
      : (event: React.MouseEvent) => {
          const target = event.target as HTMLElement;
          if (target.closest('a, button, input, .math-inline, .math-display')) return;
          onActivate?.();
        }
  };

  switch (block.kind) {
    case 'h1':
    case 'h2':
    case 'h3': {
      const level = Number(block.meta) || Number(block.kind.substring(1));
      const Tag = (`h${Math.min(6, level)}`) as keyof JSX.IntrinsicElements;
      return (
        <Tag id={`heading-${block.lineIndex}`} {...(lineAttr as object)} className={`md-block md-heading md-h${Math.min(6, level)}`}>
          <InlineContent text={block.text} notes={notes} onOpenTarget={onOpenTarget} />
        </Tag>
      );
    }
    case 'paragraph':
      return (
        <p {...commonProps}>
          <InlineContent text={block.text} notes={notes} onOpenTarget={onOpenTarget} />
        </p>
      );
    case 'bullet':
      return (
        <div {...commonProps} className={`${commonProps.className} md-bullet-block`}>
          <span className="md-bullet-marker" aria-hidden>
            •
          </span>
          <span className="md-list-text">
            <InlineContent text={block.text} notes={notes} onOpenTarget={onOpenTarget} />
          </span>
        </div>
      );
    case 'ordered':
      return (
        <div {...commonProps} className={`${commonProps.className} md-ordered-block`}>
          <span className="md-bullet-marker md-ordered-marker">{block.meta}.</span>
          <span className="md-list-text">
            <InlineContent text={block.text} notes={notes} onOpenTarget={onOpenTarget} />
          </span>
        </div>
      );
    case 'todo':
      return (
        <div {...commonProps} className={`${commonProps.className} md-todo-block${block.checked ? ' is-checked' : ''}`}>
          <button
            type="button"
            className="md-checkbox"
            aria-label={block.checked ? tr('标记为未完成') : tr('标记为已完成')}
            onClick={(event) => {
              event.stopPropagation();
              onToggleTodo?.(block.lineIndex);
            }}
          >
            {block.checked ? <CheckGlyph size={11} /> : null}
          </button>
          <span className="md-list-text">
            <InlineContent text={block.text} notes={notes} onOpenTarget={onOpenTarget} />
          </span>
        </div>
      );
    case 'quote':
      return (
        <blockquote {...commonProps}>
          <InlineContent text={block.text} notes={notes} onOpenTarget={onOpenTarget} />
        </blockquote>
      );
    case 'callout': {
      const meta = CALLOUT_LABELS[block.meta] ?? CALLOUT_LABELS.NOTE;
      // The HarmonyOS renderer keeps the callout type in Latin uppercase and the
      // whole body (including its first line) as content.
      return (
        <div {...commonProps} className={`${commonProps.className} callout callout-${block.meta.toLowerCase()}`}>
          <div className="callout-title">
            <span className="callout-mark" aria-hidden>
              {meta.mark}
            </span>
            {block.meta}
          </div>
          <div className="callout-body">
            <InlineContent text={block.text} notes={notes} onOpenTarget={onOpenTarget} />
          </div>
        </div>
      );
    }
    case 'code':
      return (
        <div {...lineAttr} className="md-block md-code">
          <CodeBlock code={block.text} language={block.meta} />
        </div>
      );
    case 'formula':
      return (
        <div {...lineAttr} className="md-block md-formula">
          <MathSpan tex={block.text} display />
        </div>
      );
    case 'hr':
      return <hr {...lineAttr} className="md-block md-hr" />;
    case 'image': {
      const src = block.meta?.trim() ?? '';
      const isRemote = /^(https?:|data:image\/|blob:)/i.test(src);
      const localUrl =
        !isRemote && src && currentNote
          ? `lexi-asset://local/?vaultId=${encodeURIComponent(currentNote.vaultId)}&notebook=${encodeURIComponent(currentNote.notebook || '默认')}&notePath=${encodeURIComponent(currentNote.path || '')}&src=${encodeURIComponent(src)}`
          : '';
      const resolvedSrc = isRemote ? src : localUrl;
      return (
        <figure {...lineAttr} className="md-block md-image">
          {resolvedSrc ? (
            <img src={resolvedSrc} alt={block.text || tr('图片')} loading="lazy" />
          ) : (
            <div className="md-image-missing">
              <span>{tr('本地图片：{0}', undefined, [src])}</span>
            </div>
          )}
          {block.text ? <figcaption>{block.text}</figcaption> : null}
        </figure>
      );
    }
    case 'embed': {
      const [baseTarget, anchorTarget = ''] = block.meta.split('#');
      const cleanBase = baseTarget.trim();
      const target =
        notesById.get(cleanBase) ??
        notes.find((note) => note.trashedAt === 0 && displayTitle(note).trim().toLowerCase() === cleanBase.toLowerCase());
      const excerpt = target ? extractEmbeddedSection(target.content, anchorTarget) : '';
      return (
        <div {...lineAttr} className="md-block md-embed">
          <div className="embed-head">
            <LinkPreviewPopover target={block.meta} showTriggerButton onOpenTarget={onOpenTarget}>
              <button type="button" className="embed-title" onClick={() => onOpenTarget?.(block.meta)}>
                {block.text || block.meta}
              </button>
            </LinkPreviewPopover>
          </div>
          <div className="embed-body">
            {excerpt ? (
              <InlineContent text={excerpt.replace(/\n+/g, ' ').slice(0, 240)} notes={notes} onOpenTarget={onOpenTarget} />
            ) : (
              tr('嵌入的笔记内容会显示在这里。')
            )}
          </div>
        </div>
      );
    }
    case 'table': {
      const table = tableData(block);
      return (
        <div {...lineAttr} className="md-block md-table-wrap">
          <table className="md-table">
            <thead>
              <tr>
                {table.rows[0]?.map((cell, index) => (
                  <th key={index} style={{ textAlign: (table.alignments[index] as 'left') || 'left' }}>
                    <InlineContent text={cell} notes={notes} onOpenTarget={onOpenTarget} />
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {table.rows.slice(1).map((row, rowIndex) => (
                <tr key={rowIndex}>
                  {row.map((cell, cellIndex) => (
                    <td key={cellIndex} style={{ textAlign: (table.alignments[cellIndex] as 'left') || 'left' }}>
                      <InlineContent text={cell} notes={notes} onOpenTarget={onOpenTarget} />
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      );
    }
    default:
      return <p {...commonProps}>{block.text}</p>;
  }
}

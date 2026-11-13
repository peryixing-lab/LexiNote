import React, { useMemo, useState } from 'react';
import katex from 'katex';
import 'katex/dist/katex.min.css';
import hljs from 'highlight.js/lib/core';
import typescript from 'highlight.js/lib/languages/typescript';
import javascript from 'highlight.js/lib/languages/javascript';
import json from 'highlight.js/lib/languages/json';
import bash from 'highlight.js/lib/languages/bash';
import python from 'highlight.js/lib/languages/python';
import css from 'highlight.js/lib/languages/css';
import xml from 'highlight.js/lib/languages/xml';
import markdown from 'highlight.js/lib/languages/markdown';
import go from 'highlight.js/lib/languages/go';
import rust from 'highlight.js/lib/languages/rust';
import java from 'highlight.js/lib/languages/java';
import sql from 'highlight.js/lib/languages/sql';
import yaml from 'highlight.js/lib/languages/yaml';
import cpp from 'highlight.js/lib/languages/cpp';
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
import { CheckGlyph } from './Symbols';
import { tr } from '../core/i18n';

hljs.registerLanguage('typescript', typescript);
hljs.registerLanguage('javascript', javascript);
hljs.registerLanguage('json', json);
hljs.registerLanguage('bash', bash);
hljs.registerLanguage('python', python);
hljs.registerLanguage('css', css);
hljs.registerLanguage('html', xml);
hljs.registerLanguage('markdown', markdown);
hljs.registerLanguage('go', go);
hljs.registerLanguage('rust', rust);
hljs.registerLanguage('java', java);
hljs.registerLanguage('sql', sql);
hljs.registerLanguage('yaml', yaml);
hljs.registerLanguage('cpp', cpp);

const LANGUAGE_ALIASES: Record<string, string> = {
  ts: 'typescript',
  tsx: 'typescript',
  js: 'javascript',
  jsx: 'javascript',
  sh: 'bash',
  shell: 'bash',
  zsh: 'bash',
  py: 'python',
  yml: 'yaml',
  xml: 'html',
  vue: 'html',
  c: 'cpp',
  'c++': 'cpp',
  h: 'cpp'
};

const CALLOUT_LABELS: Record<string, { label: string; mark: string }> = {
  NOTE: { label: '注意', mark: '✦' },
  TIP: { label: '提示', mark: '✦' },
  IMPORTANT: { label: '重要', mark: '!' },
  WARNING: { label: '警告', mark: '△' },
  CAUTION: { label: '谨慎', mark: '⚑' },
  QUESTION: { label: '问题', mark: '?' },
  EXAMPLE: { label: '示例', mark: '≡' },
  QUOTE: { label: '引用', mark: '“' },
  SUCCESS: { label: '完成', mark: '✓' },
  ABSTRACT: { label: '摘要', mark: '§' },
  TODO: { label: '待办', mark: '☐' }
};

export function renderMath(tex: string, displayMode: boolean): string {
  try {
    return katex.renderToString(tex, {
      displayMode,
      throwOnError: true,
      errorColor: 'var(--error)',
      strict: false,
      trust: false,
      output: 'html'
    });
  } catch {
    return '';
  }
}

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
  const rendered = useMemo(() => {
    const lang = LANGUAGE_ALIASES[language.toLowerCase()] ?? language.toLowerCase();
    try {
      if (lang && hljs.getLanguage(lang)) {
        return hljs.highlight(code, { language: lang, ignoreIllegals: true }).value;
      }
      return hljs.highlightAuto(code).value;
    } catch {
      return code.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    }
  }, [code, language]);

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
            const internal = notes.some(
              (note) => note.id === target || displayTitle(note).trim().toLowerCase() === target.toLowerCase()
            );
            return (
              <a
                key={span.id}
                className={internal ? 'wiki-link' : 'md-link'}
                href="#"
                onClick={(event) => {
                  event.preventDefault();
                  event.stopPropagation();
                  onOpenTarget?.(target);
                }}
              >
                {span.text}
              </a>
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
  onOpenTarget?: (target: string) => void;
  onToggleTodo?: (lineIndex: number) => void;
  anchorPrefix?: string;
  compact?: boolean;
}

/** Read-only renderer shared by reading mode, previews and exported surfaces. */
export function MarkdownBlocks({
  content,
  notes = [],
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
      return (
        <figure {...lineAttr} className="md-block md-image">
          {isRemote ? (
            <img src={src} alt={block.text || tr('图片')} loading="lazy" />
          ) : (
            <div className="md-image-missing">
              <span>{tr('本地图片：{0}', undefined, [src])}</span>
              <span>
                {tr('Windows 版暂不支持直接读取外部图片路径，请使用在线图片或粘贴图片链接。')}
              </span>
            </div>
          )}
          {block.text ? <figcaption>{block.text}</figcaption> : null}
        </figure>
      );
    }
    case 'embed': {
      const target = notesById.get(block.meta) ?? notes.find((note) => displayTitle(note) === block.meta);
      const excerpt = target ? extractEmbeddedSection(target.content, '') : '';
      return (
        <div {...lineAttr} className="md-block md-embed">
          <button type="button" className="embed-title" onClick={() => onOpenTarget?.(block.meta)}>
            {block.text || block.meta}
          </button>
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

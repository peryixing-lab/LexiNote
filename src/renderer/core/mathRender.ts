import katex from 'katex';
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

export const LANGUAGE_ALIASES: Record<string, string> = {
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

export const CALLOUT_LABELS: Record<string, { label: string; mark: string }> = {
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

export function escapeHtml(raw: string): string {
  return raw
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

export function renderMathHtml(tex: string, displayMode: boolean): string {
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

export function highlightCodeHtml(code: string, language: string): string {
  const lang = LANGUAGE_ALIASES[language.toLowerCase()] ?? language.toLowerCase();
  try {
    if (lang && hljs.getLanguage(lang)) {
      return hljs.highlight(code, { language: lang, ignoreIllegals: true }).value;
    }
    return hljs.highlightAuto(code).value;
  } catch {
    return escapeHtml(code);
  }
}

'use strict';

const MarkdownIt = require('markdown-it');

const parser = new MarkdownIt({ html: false, breaks: true, linkify: true });
const WIKILINK_TEXT_RE = /\[\[([^\]\n|]+?)(?:\|([^\]\n]+?))?\]\]/g;

function createElement(tag, className, textValue) {
  const el = document.createElement(tag);
  if (className) {
    el.className = className;
  }
  if (textValue !== undefined && textValue !== null) {
    el.textContent = String(textValue);
  }
  return el;
}

function appendTextNode(parent, value) {
  const str = String(value || '');
  if (typeof document.createTextNode === 'function') {
    parent.appendChild(document.createTextNode(str));
  } else {
    parent.appendChild(createElement('span', '', str));
  }
}

function appendTextWithWikiLinks(parent, rawText, options) {
  const value = String(rawText || '');
  WIKILINK_TEXT_RE.lastIndex = 0;
  let lastIndex = 0;
  let match = WIKILINK_TEXT_RE.exec(value);
  if (!match) {
    appendTextNode(parent, value);
    return;
  }

  while (match) {
    if (match.index > lastIndex) {
      appendTextNode(parent, value.slice(lastIndex, match.index));
    }
    const target = match[1].trim();
    const label = (match[2] || match[1].replace(/\.md$/i, '')).trim();
    const link = createElement('a', 'harness-wikilink', `[[${label}]]`);
    const href = `wiki:${target}`;
    link.setAttribute('href', `#`);
    link.setAttribute('title', `打开笔记：${target}`);
    link.addEventListener('click', (event) => {
      event.preventDefault();
      if (options && typeof options.onLink === 'function') {
        options.onLink(href);
      }
    });
    parent.appendChild(link);
    lastIndex = match.index + match[0].length;
    match = WIKILINK_TEXT_RE.exec(value);
  }

  if (lastIndex < value.length) {
    appendTextNode(parent, value.slice(lastIndex));
  }
}

function isUnsafeHref(href) {
  const clean = String(href || '').trim();
  return /^(?:javascript|vbscript|data):/i.test(clean);
}

function renderInline(tokens, parent, options, inListItem) {
  if (!Array.isArray(tokens)) {
    return;
  }
  const stack = [parent];
  const top = () => stack[stack.length - 1];
  let checkedListItem = false;

  for (let i = 0; i < tokens.length; i += 1) {
    const token = tokens[i];
    if (token.type === 'text') {
      let textContent = token.content || '';
      if (inListItem && !checkedListItem && i === 0) {
        checkedListItem = true;
        const taskMatch = /^\[([ xX])\]\s+([\s\S]*)$/.exec(textContent);
        if (taskMatch) {
          const box = document.createElement('input');
          box.type = 'checkbox';
          box.disabled = true;
          box.checked = taskMatch[1].toLowerCase() === 'x';
          top().appendChild(box);
          appendTextNode(top(), ' ');
          textContent = taskMatch[2];
        }
      }
      if (textContent) {
        appendTextWithWikiLinks(top(), textContent, options);
      }
    } else if (token.type === 'code_inline') {
      top().appendChild(createElement('code', '', token.content));
    } else if (token.type === 'softbreak') {
      appendTextNode(top(), '\n');
    } else if (token.type === 'hardbreak') {
      top().appendChild(document.createElement('br'));
    } else if (token.type === 'image') {
      const alt = token.content || (typeof token.attrGet === 'function' ? token.attrGet('alt') : '') || '图片';
      top().appendChild(createElement('span', 'harness-inline-img', `[${alt}]`));
    } else if (token.nesting === 1) {
      let node;
      if (token.type === 'link_open') {
        const rawHref = typeof token.attrGet === 'function' ? (token.attrGet('href') || '') : '';
        const href = isUnsafeHref(rawHref) ? '#' : rawHref;
        node = document.createElement('a');
        node.className = 'harness-note-link';
        node.setAttribute('href', href || '#');
        node.setAttribute('title', href);
        if (!isUnsafeHref(rawHref)) {
          node.addEventListener('click', (event) => {
            event.preventDefault();
            if (options && typeof options.onLink === 'function') {
              options.onLink(rawHref);
            }
          });
        }
      } else {
        node = document.createElement(token.tag || 'span');
      }
      top().appendChild(node);
      stack.push(node);
    } else if (token.nesting === -1) {
      if (stack.length > 1) {
        stack.pop();
      }
    }
  }
}

/** Renders Markdown safely via DOM nodes (zero innerHTML) with wiki/note link callbacks. */
function renderMarkdown(source, optionsOrCallback) {
  const options = typeof optionsOrCallback === 'function'
    ? { onLink: optionsOrCallback }
    : (optionsOrCallback && typeof optionsOrCallback === 'object' ? optionsOrCallback : {});
  const root = createElement('div', 'harness-markdown');
  const textValue = typeof source === 'string' ? source : String(source || '');
  if (!textValue.trim()) {
    return root;
  }

  const tokens = parser.parse(textValue, {});
  const stack = [root];
  const top = () => stack[stack.length - 1];
  let inlineTaskConsumed = false;

  for (let i = 0; i < tokens.length; i += 1) {
    const token = tokens[i];
    if (token.type === 'list_item_open') {
      inlineTaskConsumed = false;
    }
    if (token.type === 'inline') {
      const parentEl = top();
      const inListItem = !inlineTaskConsumed && stack.some((el) => String(el.tagName || '').toLowerCase() === 'li');
      if (inListItem) {
        inlineTaskConsumed = true;
      }
      renderInline(token.children || [], parentEl, options, inListItem);
    } else if (token.type === 'fence' || token.type === 'code_block') {
      const pre = document.createElement('pre');
      const code = document.createElement('code');
      const info = String(token.info || '').trim().split(/\s+/)[0];
      if (info) {
        code.setAttribute('data-lang', info);
      }
      code.textContent = token.content || '';
      pre.appendChild(code);
      top().appendChild(pre);
    } else if (token.type === 'hr') {
      top().appendChild(document.createElement('hr'));
    } else if (token.nesting === 1) {
      const node = document.createElement(token.tag || 'div');
      top().appendChild(node);
      stack.push(node);
    } else if (token.nesting === -1) {
      if (stack.length > 1) {
        stack.pop();
      }
    }
  }

  return root;
}

module.exports = { renderMarkdown };

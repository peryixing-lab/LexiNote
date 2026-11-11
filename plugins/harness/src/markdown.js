'use strict';

const MarkdownIt = require('markdown-it');
const parser = new MarkdownIt({ html: false, breaks: true, linkify: true });

/** Render parsed Markdown tokens into DOM. Model text never becomes raw HTML. */
function renderMarkdown(source, onLink) {
  const root = document.createElement('div');
  root.className = 'harness-markdown';
  const allowed = new Set(['p', 'strong', 'em', 's', 'blockquote', 'ul', 'ol', 'li',
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'table', 'thead', 'tbody', 'tr', 'th', 'td']);

  function append(tokens, target) {
    const stack = [target];
    for (let index = 0; index < tokens.length; index += 1) {
      const token = tokens[index];
      const parent = stack[stack.length - 1];
      if (token.type === 'inline') { append(token.children || [], parent); continue; }
      if (token.type === 'text') {
        const task = index === 0 && /^\[([ xX])\]\s+/.exec(token.content);
        if (task && target.tagName === 'P' && target.parentNode && target.parentNode.tagName === 'LI') {
          target.parentNode.classList.add('harness-task-item');
          const checkbox = document.createElement('input');
          checkbox.type = 'checkbox';
          checkbox.disabled = true;
          checkbox.checked = task[1].toLowerCase() === 'x';
          checkbox.setAttribute('aria-label', checkbox.checked ? '已完成' : '未完成');
          parent.appendChild(checkbox);
        }
        const node = document.createElement('span');
        node.textContent = task && target.tagName === 'P' && target.parentNode && target.parentNode.tagName === 'LI'
          ? token.content.slice(task[0].length) : token.content;
        parent.appendChild(node);
      } else if (token.type === 'code_inline') {
        const code = document.createElement('code');
        code.textContent = token.content;
        parent.appendChild(code);
      } else if (token.type === 'fence' || token.type === 'code_block') {
        const pre = document.createElement('pre');
        const code = document.createElement('code');
        code.textContent = token.content;
        pre.appendChild(code);
        parent.appendChild(pre);
      } else if (token.type === 'softbreak' || token.type === 'hardbreak' || token.type === 'hr') {
        parent.appendChild(document.createElement(token.type === 'hr' ? 'hr' : 'br'));
      } else if (token.type === 'image') {
        const alt = document.createElement('span');
        alt.textContent = `[图片：${token.content || '图片'}]`;
        parent.appendChild(alt);
      } else if (token.nesting === 1) {
        const node = document.createElement(token.tag === 'a' ? 'a' : (allowed.has(token.tag) ? token.tag : 'span'));
        if (token.tag === 'a') {
          const href = token.attrGet('href') || '';
          if (/^(https?:|mailto:)/i.test(href) || (!/^[a-z][a-z\d+.-]*:/i.test(href) && !href.startsWith('//'))) {
            node.setAttribute('href', href);
            node.setAttribute('title', href);
            node.addEventListener('click', (event) => {
              event.preventDefault();
              if (onLink) { onLink(href); }
            });
          }
        }
        if (token.tag === 'ol' && token.attrGet('start')) { node.setAttribute('start', token.attrGet('start')); }
        parent.appendChild(node);
        stack.push(node);
      } else if (token.nesting === -1 && stack.length > 1) {
        stack.pop();
      }
    }
  }
  append(parser.parse(String(source || ''), {}), root);
  return root;
}

module.exports = { renderMarkdown };

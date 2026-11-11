'use strict';

/**
 * Minimal DOM used by the plugin runtime regressions.
 *
 * It implements exactly the surface the SDK's view renderer and the Harness chat view use:
 * element creation, class lists, text content, appends/replacements, listeners, focus and a
 * class selector. It is a test double, not a browser; layout and real input handling still
 * need device verification.
 */

class FakeClassList {
  constructor() {
    this.values = new Set();
  }
  add(...names) { names.forEach((name) => { if (name) { this.values.add(String(name)); } }); }
  remove(...names) { names.forEach((name) => this.values.delete(String(name))); }
  contains(name) { return this.values.has(String(name)); }
  toggle(name, force) {
    const next = force === undefined ? !this.contains(name) : force === true;
    if (next) { this.values.add(String(name)); } else { this.values.delete(String(name)); }
    return next;
  }
  get value() { return Array.from(this.values).join(' '); }
}

class FakeElement {
  constructor(tagName) {
    this.tagName = String(tagName || 'div').toUpperCase();
    this.children = [];
    this.parentNode = null;
    this.ownerDocument = null;
    this.classList = new FakeClassList();
    this.attributes = new Map();
    this.listeners = new Map();
    this.style = {};
    this._text = '';
    this.id = '';
    this.disabled = false;
    this.value = '';
    this.type = '';
    this.placeholder = '';
    this.rows = 0;
    this.selected = false;
    this.checked = false;
    this.scrollTop = 0;
    this.scrollHeight = 0;
  }

  get className() { return this.classList.value; }
  set className(value) {
    this.classList.values = new Set(String(value || '').split(/\s+/).filter(Boolean));
  }

  get textContent() {
    if (this.children.length === 0) { return this._text; }
    return this.children.map((child) => child.textContent).join('');
  }
  set textContent(value) {
    this.children = [];
    this._text = String(value === undefined || value === null ? '' : value);
  }

  get outerHTML() {
    return `<${this.tagName.toLowerCase()} class="${this.className}">${this.textContent}</${this.tagName.toLowerCase()}>`;
  }

  appendChild(child) {
    if (!child) { throw new Error('appendChild(null)'); }
    if (child.parentNode) { child.parentNode.removeChildNode(child); }
    child.parentNode = this;
    child.ownerDocument = this.ownerDocument || child.ownerDocument;
    this.children.push(child);
    return child;
  }

  removeChildNode(child) {
    const index = this.children.indexOf(child);
    if (index >= 0) { this.children.splice(index, 1); }
    child.parentNode = null;
  }

  replaceChildren(...nodes) {
    for (const child of this.children) { child.parentNode = null; }
    this.children = [];
    for (const node of nodes) { this.appendChild(node); }
  }

  replaceChild(next, previous) {
    const index = this.children.indexOf(previous);
    if (index < 0) { throw new Error('replaceChild: previous node is not a child'); }
    if (next.parentNode) { next.parentNode.removeChildNode(next); }
    next.parentNode = this;
    next.ownerDocument = this.ownerDocument || next.ownerDocument;
    this.children[index] = next;
    previous.parentNode = null;
    return previous;
  }

  remove() {
    if (this.parentNode) { this.parentNode.removeChildNode(this); }
  }

  setAttribute(name, value) { this.attributes.set(String(name), String(value)); }
  getAttribute(name) { return this.attributes.has(String(name)) ? this.attributes.get(String(name)) : null; }

  addEventListener(type, listener) {
    const key = String(type);
    const list = this.listeners.get(key) || [];
    list.push(listener);
    this.listeners.set(key, list);
  }

  removeEventListener(type, listener) {
    const list = this.listeners.get(String(type));
    if (!list) { return; }
    const index = list.indexOf(listener);
    if (index >= 0) { list.splice(index, 1); }
  }

  dispatchEvent(event) {
    const payload = event || {};
    const record = Object.assign({
      type: payload.type || 'event',
      target: this,
      currentTarget: this,
      preventDefault() {},
      stopPropagation() {}
    }, payload);
    const list = this.listeners.get(record.type) || [];
    for (const listener of list.slice()) {
      listener.call(this, record);
    }
    return true;
  }

  focus() {
    if (this.ownerDocument) { this.ownerDocument.activeElement = this; }
  }

  matches(selector) {
    const value = String(selector || '').trim();
    if (value.startsWith('.')) { return this.classList.contains(value.slice(1)); }
    if (value.startsWith('#')) { return this.id === value.slice(1); }
    return this.tagName === value.toUpperCase();
  }

  querySelector(selector) {
    const found = this.querySelectorAll(selector);
    return found.length > 0 ? found[0] : null;
  }

  querySelectorAll(selector) {
    const matches = [];
    const walk = (node) => {
      for (const child of node.children) {
        if (child.matches(selector)) { matches.push(child); }
        walk(child);
      }
    };
    walk(this);
    return matches;
  }

  findAllByText(text) {
    const found = [];
    const walk = (node) => {
      if (node.children.length === 0 && node._text === text) { found.push(node); }
      for (const child of node.children) { walk(child); }
    };
    walk(this);
    return found;
  }
}

function createDocument() {
  const document = {
    activeElement: null,
    body: null,
    createElement(tagName) {
      const node = new FakeElement(tagName);
      node.ownerDocument = document;
      return node;
    },
    getElementById(id) {
      const walk = (node) => {
        for (const child of node.children) {
          if (child.id === id) { return child; }
          const found = walk(child);
          if (found) { return found; }
        }
        return null;
      };
      return document.body ? walk(document.body) : null;
    }
  };
  document.body = new FakeElement('body');
  document.body.ownerDocument = document;
  document.head = new FakeElement('head');
  document.head.ownerDocument = document;
  return document;
}

/** Installs a fresh document on globalThis and returns it. */
function installDom() {
  const document = createDocument();
  globalThis.document = document;
  return document;
}

function removeDom() {
  try { delete globalThis.document; } catch (error) { globalThis.document = undefined; }
}

/** Collects visible text lines, useful for assertions. */
function textLines(root) {
  const lines = [];
  const walk = (node) => {
    if (node.children.length === 0 && node._text) {
      lines.push(node._text);
      return;
    }
    for (const child of node.children) { walk(child); }
  };
  walk(root);
  return lines;
}

module.exports = { FakeElement, createDocument, installDom, removeDom, textLines };

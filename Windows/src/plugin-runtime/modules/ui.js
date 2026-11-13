'use strict';

// The plugin owns this local DOM surface. File and network access still go through
// the same capability checked bridge; rendering a view adds no host permissions.
function createPluginSurface() {
  if (typeof document === 'undefined' || !document.body) { return null; }
  const proto = document.createElement('div').constructor.prototype;
  const elementProto = Object.getPrototypeOf(proto);
  function method(name, callback) {
    if (!elementProto[name]) { Object.defineProperty(elementProto, name, { configurable: true, value: callback }); }
  }
  method('empty', function () { this.replaceChildren(); return this; });
  method('setText', function (text) { this.textContent = text; return this; });
  method('addClass', function (...names) { this.classList.add(...names); return this; });
  method('removeClass', function (...names) { this.classList.remove(...names); return this; });
  method('toggleClass', function (name, force) { this.classList.toggle(name, force); return this; });
  method('setAttr', function (name, value) { this.setAttribute(name, value); return this; });
  method('setAttrs', function (attrs) { Object.keys(attrs).forEach(key => this.setAttribute(key, attrs[key])); return this; });
  method('setCssProps', function (props) { Object.keys(props).forEach(key => this.style.setProperty(key, props[key])); return this; });
  method('onClickEvent', function (callback) { this.addEventListener('click', callback); return this; });
  method('createEl', function (tag, options, callback) {
    const el = document.createElement(tag);
    const opts = typeof options === 'string' ? { cls: options } : (options || {});
    if (opts.cls) { el.className = Array.isArray(opts.cls) ? opts.cls.join(' ') : opts.cls; }
    if (opts.text !== undefined) { el.textContent = opts.text; }
    if (opts.attr) { Object.keys(opts.attr).forEach(key => el.setAttribute(key, opts.attr[key])); }
    if (opts.type) { el.type = opts.type; }
    if (opts.parent) { opts.parent.appendChild(el); } else { this.appendChild(el); }
    if (typeof callback === 'function') { callback(el); }
    return el;
  });
  method('createDiv', function (options, callback) { return this.createEl('div', options, callback); });
  method('createSpan', function (options, callback) { return this.createEl('span', options, callback); });
  let root = document.getElementById('plugin-surface');
  if (!root) { root = document.body.createDiv({ attr: { id: 'plugin-surface' } }); }
  root.replaceChildren();
  const style = document.createElement('style');
  document.head.appendChild(style);

  class PluginSettingTab {
    constructor(app, plugin) { this.app = app; this.plugin = plugin; this.containerEl = document.createElement('div'); }
    async display() {
      if (typeof this.getSettingDefinitions !== 'function') { return; }
      this.containerEl.replaceChildren();
      const data = Object.assign({}, (await this.plugin.loadData()) || {});
      for (const definition of this.getSettingDefinitions()) {
        if (definition.type === 'heading') { this.containerEl.createEl('h4', { text: definition.name }); continue; }
        const setting = new Setting(this.containerEl).setName(definition.name || definition.key);
        if (definition.desc) { setting.setDesc(definition.desc); }
        const control = new Control(setting.controlEl, definition.type === 'textarea' ? 'textarea' : 'input', definition.type === 'password' ? 'password' : 'text');
        control.setValue(data[definition.key] === undefined ? (definition.default || '') : data[definition.key]);
        control.onChange(async value => { data[definition.key] = value; await this.plugin.saveData(data); });
      }
    }
    hide() {}
  }
  class Control {
    constructor(parent, tag, type) { this.inputEl = parent.createEl(tag || 'input'); if (type) { this.inputEl.type = type; } }
    setValue(value) { if (this.inputEl.type === 'checkbox') { this.inputEl.checked = !!value; } else { this.inputEl.value = value; } return this; }
    getValue() { return this.inputEl.type === 'checkbox' ? this.inputEl.checked : this.inputEl.value; }
    setPlaceholder(text) { this.inputEl.placeholder = text; return this; }
    setDisabled(disabled) { this.inputEl.disabled = disabled; return this; }
    setButtonText(text) { this.inputEl.textContent = text; return this; }
    setCta() { this.inputEl.classList.add('mod-cta'); return this; }
    setWarning() { this.inputEl.classList.add('mod-warning'); return this; }
    setTooltip(text) { this.inputEl.title = text; return this; }
    onClick(callback) { this.inputEl.addEventListener('click', callback); return this; }
    onChange(callback) { this.inputEl.addEventListener('change', () => callback(this.getValue())); return this; }
    addOption(value, label) { this.inputEl.createEl('option', { text: label, attr: { value } }); return this; }
    addOptions(options) { Object.keys(options).forEach(key => this.addOption(key, options[key])); return this; }
    setLimits(min, max, step) { Object.assign(this.inputEl, { min, max, step }); return this; }
    setDynamicTooltip() { return this; }
  }
  class Setting {
    constructor(parent) {
      this.settingEl = parent.createDiv('setting-item');
      this.infoEl = this.settingEl.createDiv('setting-item-info');
      this.nameEl = this.infoEl.createDiv('setting-item-name');
      this.descEl = this.infoEl.createDiv('setting-item-description');
      this.controlEl = this.settingEl.createDiv('setting-item-control');
    }
    setName(text) { this.nameEl.textContent = text; return this; }
    setDesc(text) { this.descEl.replaceChildren(); this.descEl.append(text); return this; }
    setHeading() { this.settingEl.classList.add('setting-item-heading'); return this; }
    setClass(name) { this.settingEl.classList.add(name); return this; }
    setDisabled(disabled) { this.controlEl.querySelectorAll('input,button,select').forEach(el => { el.disabled = disabled; }); return this; }
    addText(callback) { callback(new Control(this.controlEl, 'input', 'text')); return this; }
    addTextArea(callback) { callback(new Control(this.controlEl, 'textarea')); return this; }
    addToggle(callback) { callback(new Control(this.controlEl, 'input', 'checkbox')); return this; }
    addDropdown(callback) { callback(new Control(this.controlEl, 'select')); return this; }
    addButton(callback) { callback(new Control(this.controlEl, 'button')); return this; }
    addSlider(callback) { callback(new Control(this.controlEl, 'input', 'range')); return this; }
  }
  const openModals = new Set();
  function emitModalState() {
    if (typeof globalThis !== 'undefined' && typeof globalThis.__lexiDesktopUiHook === 'function') {
      try { globalThis.__lexiDesktopUiHook({ type: 'modal-state', openCount: openModals.size }); } catch (error) { /* ignore */ }
    }
  }
  class Modal {
    constructor(app) {
      this.app = app;
      this.modalEl = document.createElement('div'); this.modalEl.className = 'modal';
      this.titleEl = this.modalEl.createEl('h3'); this.contentEl = this.modalEl.createDiv('modal-content');
      this.modalEl.createEl('button', { text: '×', cls: 'modal-close-button' }).onclick = () => this.close();
    }
    setTitle(text) { this.titleEl.textContent = text; return this; }
    setContent(text) { this.contentEl.textContent = text; return this; }
    open() {
      root.appendChild(this.modalEl);
      openModals.add(this);
      emitModalState();
      this.onOpen();
    }
    close() {
      if (openModals.delete(this)) { emitModalState(); }
      this.onClose();
      this.modalEl.remove();
    }
    onOpen() {}
    onClose() {}
  }
  return {
    root, PluginSettingTab, Setting, Modal,
    setStyles(css) { style.textContent = css || ''; },
    dispose() {
      openModals.clear();
      emitModalState();
      root.replaceChildren();
      style.remove();
    }
  };
}

module.exports = { createPluginSurface };

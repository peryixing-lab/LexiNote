/* Appearance settings are provided by the native host, not by plugins. */
(function () {
  'use strict';
  var quick = false;
  window.lexiApplyAppearance = function (accent, size, enabled, css) {
    if (!/^#[0-9a-f]{6}$/i.test(accent)) accent = '#6E44D9';
    size = Math.max(10, Math.min(32, Number(size) || 16));
    quick = enabled === true;
    var style = document.getElementById('lexi-user-appearance');
    if (!style) {
      style = document.createElement('style');
      style.id = 'lexi-user-appearance';
      document.head.appendChild(style);
    }
    if (document.head.lastElementChild !== style) document.head.appendChild(style);
    style.textContent = 'body.theme-light, body.theme-dark {' +
      '--interactive-accent:' + accent + ';--interactive-accent-hover:' + accent + ';' +
      '--font-text-size:' + size + 'px;}' +
      '.markdown-source-view .cm-editor,.markdown-rendered {font-size:' + size + 'px;}\n' + (css || '');
  };
  new MutationObserver(function () {
    var style = document.getElementById('lexi-user-appearance');
    if (style && document.head.lastElementChild !== style) document.head.appendChild(style);
  }).observe(document.head, { childList: true });
  document.addEventListener('wheel', function (event) {
    if (!quick || !event.ctrlKey || !event.deltaY || !event.target.closest('.view-body')) return;
    if (!window.__lexiHandshake || typeof window.__lexiHandshake.zoom !== 'function') return;
    event.preventDefault();
    window.__lexiHandshake.zoom(event.deltaY < 0 ? 1 : -1);
  }, { passive: false });
})();

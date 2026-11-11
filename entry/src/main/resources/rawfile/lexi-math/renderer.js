/* Offline formula view. All note text enters through textContent or KaTeX. */
(function () {
  'use strict';

  const content = document.getElementById('content');
  let gestureStart = null;
  let gestureMoved = false;

  function bridge(method, argument) {
    const native = window.lexiMathBridge;
    if (native && typeof native[method] === 'function') {
      if (argument === undefined) native[method]();
      else native[method](argument);
    }
  }

  function appendMath(segment, displayMode) {
    const node = document.createElement('span');
    node.className = displayMode ? 'math-display' : 'math-inline';
    try {
      window.katex.render(segment.text, node, {
        displayMode: displayMode,
        output: 'htmlAndMathml',
        throwOnError: true,
        strict: 'ignore',
        trust: false,
        maxExpand: 1000,
        maxSize: 20,
        // A fresh object prevents a formula's \gdef leaking into another one.
        macros: {}
      });
    } catch (_) {
      node.classList.add('math-error');
      node.textContent = segment.text;
      node.title = '公式语法有误或暂不支持，显示 LaTeX 原文';
    }
    content.appendChild(node);
  }

  function appendText(segment) {
    const isLink = segment.kind === 'link' || segment.kind === 'url';
    const node = document.createElement(isLink ? 'a' : 'span');
    node.textContent = segment.text;
    if (isLink) {
      // Native code resolves the ID against its parsed spans; user URLs never
      // become navigation targets inside this local Web view.
      node.setAttribute('role', 'link');
      node.setAttribute('tabindex', '0');
      node.dataset.spanId = segment.id;
      node.addEventListener('keydown', function (event) {
        if (event.key === 'Enter' || event.key === ' ') {
          event.preventDefault();
          bridge('activate', segment.id);
        }
      });
    } else if (['bold', 'italic', 'strike', 'highlight', 'code'].includes(segment.kind)) {
      node.className = segment.kind;
    }
    content.appendChild(node);
  }

  window.lexiRender = function (payload) {
    document.documentElement.classList.toggle('dark', payload.dark === true);
    content.classList.toggle('strong', payload.strong === true);
    content.classList.toggle('muted', payload.muted === true);
    content.classList.toggle('checked', payload.checked === true);
    content.style.fontSize = Math.max(8, Math.min(96, Number(payload.textSize) || 16)) + 'px';
    content.style.lineHeight = Math.max(12, Math.min(160, Number(payload.textLeading) || 27)) + 'px';
    content.style.textAlign = ['left', 'center', 'right'].includes(payload.alignment) ? payload.alignment : 'left';
    content.replaceChildren();
    for (const segment of payload.spans || []) {
      if (payload.displayMode || segment.kind === 'math' || segment.kind === 'math-display') {
        appendMath(segment, payload.displayMode || segment.kind === 'math-display');
      } else {
        appendText(segment);
      }
    }
    reportSize();
  };

  function reportSize() {
    // Measure content rather than the viewport, so the native Web can use async rendering.
    bridge('resize', Math.ceil(content.getBoundingClientRect().height));
  }
  new ResizeObserver(reportSize).observe(content);
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(reportSize);

  content.addEventListener('pointerdown', function (event) {
    gestureStart = { x: event.clientX, y: event.clientY };
    gestureMoved = false;
  });
  content.addEventListener('pointermove', function (event) {
    if (gestureStart && (Math.abs(event.clientX - gestureStart.x) > 5 || Math.abs(event.clientY - gestureStart.y) > 5)) {
      gestureMoved = true;
    }
  });
  content.addEventListener('pointercancel', function () { gestureMoved = true; });
  content.addEventListener('click', function (event) {
    event.preventDefault();
    event.stopPropagation();
    if (gestureMoved || String(window.getSelection() || '').length > 0) return;
    const anchor = event.target.closest('a[data-span-id]');
    if (anchor) bridge('activate', anchor.dataset.spanId);
    else bridge('edit');
    gestureStart = null;
  });
  // Even generated math cannot navigate away from the bundled renderer.
  document.addEventListener('click', function (event) {
    if (event.target.closest('a')) event.preventDefault();
  });
}());

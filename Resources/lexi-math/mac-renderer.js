(function () {
  const KATEX_MACROS = {
    '\\bm': '\\boldsymbol{#1}',
    '\\R': '\\mathbb{R}',
    '\\N': '\\mathbb{N}',
    '\\Z': '\\mathbb{Z}',
    '\\Q': '\\mathbb{Q}',
    '\\C': '\\mathbb{C}',
    '\\E': '\\mathbb{E}',
    '\\P': '\\mathbb{P}',
    '\\argmax': '\\operatorname*{arg\\,max}',
    '\\argmin': '\\operatorname*{arg\\,min}',
    '\\defeq': '\\stackrel{\\mathrm{def}}{=}',
    '\\eqdef': '\\stackrel{\\mathrm{def}}{=}',
    '\\coloneqq': '\\mathrel{:=}',
    '\\eqqcolon': '\\mathrel{=:}',
    '\\llbracket': '[\\![',
    '\\rrbracket': ']\\!]'
  };

  function collectVisualBounds(rootEl) {
    const fallback = rootEl.getBoundingClientRect();
    let minX = fallback.left;
    let minY = fallback.top;
    let maxX = fallback.right;
    let maxY = fallback.bottom;
    let found = false;

    const katexHtml = rootEl.querySelector('.katex-html');
    const targets = katexHtml
      ? katexHtml.querySelectorAll('span, svg')
      : rootEl.querySelectorAll('mjx-container, svg, path, rect, line, span');

    for (let i = 0; i < targets.length; i++) {
      const node = targets[i];
      if (node.closest && node.closest('.katex-mathml')) {
        continue;
      }
      const style = window.getComputedStyle(node);
      if (style.display === 'none' || style.visibility === 'hidden') {
        continue;
      }
      const r = node.getBoundingClientRect();
      if (!Number.isFinite(r.width) || !Number.isFinite(r.height)) {
        continue;
      }
      if (r.width <= 0.1 && r.height <= 0.1) {
        continue;
      }
      if (!found) {
        minX = r.left;
        minY = r.top;
        maxX = r.right;
        maxY = r.bottom;
        found = true;
      } else {
        if (r.left < minX) minX = r.left;
        if (r.top < minY) minY = r.top;
        if (r.right > maxX) maxX = r.right;
        if (r.bottom > maxY) maxY = r.bottom;
      }
    }

    if (!found) {
      return {
        left: fallback.left,
        top: fallback.top,
        width: Math.max(1, fallback.width),
        height: Math.max(1, fallback.height),
        bottom: fallback.bottom
      };
    }

    const padX = 3;
    const padY = 2;
    const left = Math.max(0, Math.floor(minX - padX));
    const top = Math.max(0, Math.floor(minY - padY));
    const right = Math.ceil(maxX + padX);
    const bottom = Math.ceil(maxY + padY);
    return {
      left: left,
      top: top,
      width: Math.max(1, right - left),
      height: Math.max(1, bottom - top),
      bottom: bottom
    };
  }

  function tryKatexRender(formulaEl, rawSource, displayMode) {
    if (!window.katex || typeof window.katex.render !== 'function') {
      return { ok: false, error: 'KaTeX not loaded' };
    }
    const prepared = typeof window.preprocessLatex === 'function'
      ? window.preprocessLatex(rawSource, displayMode)
      : String(rawSource || '').trim();
    const attempts = [prepared];
    if (typeof window.fallbackLatex === 'function') {
      const alt = window.fallbackLatex(prepared, displayMode);
      if (alt && alt !== prepared) {
        attempts.push(alt);
      }
    }

    let lastError = 'KaTeX render failed';
    for (let i = 0; i < attempts.length; i++) {
      try {
        formulaEl.innerHTML = '';
        window.katex.render(attempts[i], formulaEl, {
          displayMode: !!displayMode,
          throwOnError: true,
          strict: false,
          trust: false,
          macros: KATEX_MACROS
        });
        return { ok: true, engine: 'katex' };
      } catch (err) {
        lastError = (err && err.message) ? String(err.message) : String(err);
      }
    }
    return { ok: false, error: lastError };
  }

  async function tryMathJaxRender(formulaEl, rawSource, displayMode, colorHex) {
    if (!window.MathJax) {
      return { ok: false, error: 'MathJax not loaded' };
    }
    if (window.MathJax.startup && window.MathJax.startup.promise) {
      await window.MathJax.startup.promise;
    }
    if (typeof window.renderFormulaSvg !== 'function' || typeof window.MathJax.tex2svg !== 'function') {
      return { ok: false, error: 'MathJax tex2svg unavailable' };
    }
    const rendered = window.renderFormulaSvg(rawSource, !!displayMode);
    if (rendered.querySelector('[data-mjx-error]')) {
      const errNode = rendered.querySelector('[data-mjx-error]');
      const reason = errNode ? (errNode.getAttribute('data-mjx-error') || errNode.textContent || 'Invalid LaTeX') : 'Invalid LaTeX';
      return { ok: false, error: String(reason).trim() };
    }
    const svg = rendered.querySelector('svg');
    if (svg) {
      svg.setAttribute('color', colorHex);
      svg.style.color = colorHex;
      if (typeof window.LEXI_SVG_STYLES === 'string' && !svg.querySelector('style[data-lexi]')) {
        const styleEl = document.createElementNS('http://www.w3.org/2000/svg', 'style');
        styleEl.setAttribute('data-lexi', '1');
        styleEl.textContent = window.LEXI_SVG_STYLES;
        svg.insertBefore(styleEl, svg.firstChild);
      }
    }
    formulaEl.innerHTML = '';
    formulaEl.appendChild(rendered);
    return { ok: true, engine: 'mathjax' };
  }

  function waitNextFrames() {
    return new Promise(function (resolve) {
      var settled = false;
      function finish() {
        if (!settled) {
          settled = true;
          resolve();
        }
      }
      setTimeout(finish, 32);
      if (typeof requestAnimationFrame === 'function') {
        requestAnimationFrame(function () {
          setTimeout(finish, 0);
        });
      }
    });
  }

  function waitFontsReadyBounded() {
    if (!document.fonts || !document.fonts.ready) {
      return Promise.resolve();
    }
    return Promise.race([
      document.fonts.ready,
      new Promise(function (resolve) { setTimeout(resolve, 1200); })
    ]);
  }

  window.lexiPrepareFormula = async function (payload) {
    try {
      const source = String(payload && payload.latex ? payload.latex : '').trim();
      const displayMode = !!(payload && payload.displayMode);
      const fontSize = Math.max(10, Math.min(44, Number(payload && payload.fontSize) || 16));
      const colorHex = String((payload && payload.colorHex) || '#231b36');

      if (!source) {
        return JSON.stringify({ ok: false, error: 'Empty formula' });
      }

      const stage = document.getElementById('stage');
      const strut = document.getElementById('strut');
      const baselineAnchor = document.getElementById('baseline-anchor');
      const formulaEl = document.getElementById('formula');

      stage.style.color = colorHex;
      strut.style.fontSize = fontSize + 'px';
      formulaEl.style.fontSize = fontSize + 'px';
      formulaEl.style.color = colorHex;
      formulaEl.className = displayMode ? 'block-mode' : '';
      formulaEl.innerHTML = '';

      let outcome = tryKatexRender(formulaEl, source, displayMode);
      if (!outcome.ok) {
        const mjOutcome = await tryMathJaxRender(formulaEl, source, displayMode, colorHex);
        if (mjOutcome.ok) {
          outcome = mjOutcome;
        } else {
          return JSON.stringify({
            ok: false,
            error: mjOutcome.error || outcome.error || 'LaTeX syntax error'
          });
        }
      }

      await waitFontsReadyBounded();
      void formulaEl.offsetHeight;
      await waitNextFrames();

      const bounds = collectVisualBounds(formulaEl);
      const anchorRect = baselineAnchor.getBoundingClientRect();
      const descent = Math.max(0, (bounds.top + bounds.height) - anchorRect.bottom);

      return JSON.stringify({
        ok: true,
        engine: outcome.engine,
        x: bounds.left,
        y: bounds.top,
        width: bounds.width,
        height: bounds.height,
        descent: descent
      });
    } catch (err) {
      return JSON.stringify({
        ok: false,
        error: (err && err.message) ? String(err.message) : String(err)
      });
    }
  };
})();

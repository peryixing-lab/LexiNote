/* One local background renderer serves all formulas; user source is never injected as HTML. */
const LEXI_SVG_STYLES = [
  'svg{overflow:visible}',
  'path[data-c],use[data-c]{stroke-width:3}',
  'g[data-mml-node="mtable"]>line[data-line],svg[data-table]>g>line[data-line],g[data-mml-node="mtable"]>rect[data-frame],svg[data-table]>g>rect[data-frame]{stroke-width:70px;fill:none}',
  'g[data-mml-node="mtable"]>.mjx-dashed,svg[data-table]>g>.mjx-dashed{stroke-dasharray:140}',
  'g[data-mml-node="mtable"]>.mjx-dotted,svg[data-table]>g>.mjx-dotted{stroke-linecap:round;stroke-dasharray:0,140}',
  'g[data-mml-node="mtable"]>g>svg{overflow:visible}'
].join('');

function stripLatexComments(source) {
  const lines = source.split(/\r?\n/);
  const cleaned = [];
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    let cut = -1;
    for (let j = 0; j < line.length; j++) {
      if (line[j] === '%') {
        let slashes = 0;
        for (let k = j - 1; k >= 0 && line[k] === '\\'; k--) { slashes++; }
        if (slashes % 2 === 0) { cut = j; break; }
      }
    }
    cleaned.push(cut >= 0 ? line.substring(0, cut) : line);
  }
  return cleaned.join('\n');
}

function normalizeTopLevelMultiline(source, display) {
  let braceDepth = 0;
  let envDepth = 0;
  let leftRightDepth = 0;
  let hasTopLevelBreak = false;
  let hasTopLevelAmp = false;
  for (let i = 0; i < source.length; i++) {
    const ch = source[i];
    if (ch === '\\') {
      const next = source[i + 1] || '';
      if (next === '\\') {
        if (braceDepth === 0 && envDepth === 0 && leftRightDepth === 0) { hasTopLevelBreak = true; }
        i++;
        continue;
      }
      if (!/[A-Za-z]/.test(next)) {
        i++;
        continue;
      }
      let end = i + 1;
      while (end < source.length && /[A-Za-z]/.test(source[end])) { end++; }
      const cmd = source.substring(i + 1, end);
      if (cmd === 'begin') { envDepth++; }
      else if (cmd === 'end') { envDepth = Math.max(0, envDepth - 1); }
      else if (cmd === 'left') { leftRightDepth++; }
      else if (cmd === 'right') { leftRightDepth = Math.max(0, leftRightDepth - 1); }
      else if ((cmd === 'newline' || cmd === 'cr') && braceDepth === 0 && envDepth === 0 && leftRightDepth === 0) {
        hasTopLevelBreak = true;
      }
      i = end - 1;
      continue;
    }
    if (ch === '{') { braceDepth++; }
    else if (ch === '}') { braceDepth = Math.max(0, braceDepth - 1); }
    else if (ch === '&' && braceDepth === 0 && envDepth === 0 && leftRightDepth === 0) {
      hasTopLevelAmp = true;
    }
  }
  if (!hasTopLevelBreak && !hasTopLevelAmp) { return source; }
  if (display) {
    const env = hasTopLevelAmp ? 'align*' : 'gather*';
    return '\\begin{' + env + '}\n' + source + '\n\\end{' + env + '}';
  }
  const env = hasTopLevelAmp ? 'aligned' : 'gathered';
  return '\\begin{' + env + '}\n' + source + '\n\\end{' + env + '}';
}

function preprocessLatex(source, display) {
  let text = stripLatexComments(String(source || '')).trim();
  text = text
    .replace(/\\(left|bigl|Bigl|biggl|Biggl)\s*\\llbracket/g, '\\$1[\\!\\$1[')
    .replace(/\\(right|bigr|Bigr|biggr|Biggr)\s*\\rrbracket/g, '\\$1]\\!\\$1]')
    .replace(/\\(left|bigl|Bigl|biggl|Biggl)\s*\\lBrace/g, '\\$1\\{\\!\\$1|')
    .replace(/\\(right|bigr|Bigr|biggr|Biggr)\s*\\rBrace/g, '\\$1|\\!\\$1\\}')
    .replace(/\\begin\{tabular\}/g, '\\begin{array}')
    .replace(/\\end\{tabular\}/g, '\\end{array}');
  return normalizeTopLevelMultiline(text, display);
}

function fallbackLatex(source, display) {
  let text = source
    .replace(/\\begin\{(d?cases|rcases)\*\}/g, '\\begin{$1}')
    .replace(/\\end\{(d?cases|rcases)\*\}/g, '\\end{$1}')
    .replace(/\\begin\{(?:sub)?numcases\}\{([^}]*)\}/g, '$1 \\begin{dcases}')
    .replace(/\\end\{(?:sub)?numcases\}/g, '\\end{dcases}');
  if (display && /\\tag\*?\{/.test(text)) {
    text = text
      .replace(/^\\begin\{aligned\}([\s\S]*)\\end\{aligned\}$/, '\\begin{align*}$1\\end{align*}')
      .replace(/^\\begin\{gathered\}([\s\S]*)\\end\{gathered\}$/, '\\begin{gather*}$1\\end{gather*}');
  }
  return text;
}

function renderFormulaSvg(source, display) {
  const normalized = preprocessLatex(source, display);
  if (typeof MathJax.texReset === 'function') { MathJax.texReset(); }
  let el = MathJax.tex2svg(normalized, { display });
  if (el.querySelector('[data-mjx-error]')) {
    const fallback = fallbackLatex(normalized, display);
    if (fallback !== normalized) {
      if (typeof MathJax.texReset === 'function') { MathJax.texReset(); }
      el = MathJax.tex2svg(fallback, { display });
    }
    if (el.querySelector('[data-mjx-error]') && !display && /\\begin\{(align|gather|multline|flalign|equation)\*?\}/.test(fallback)) {
      if (typeof MathJax.texReset === 'function') { MathJax.texReset(); }
      el = MathJax.tex2svg(fallback, { display: true });
    }
  }
  return el;
}

function loadImageFromSvg(svgString) {
  return new Promise((resolve, reject) => {
    const image = new Image();
    image.onload = () => resolve(image);
    image.onerror = () => reject(new Error('SVG image load failed'));
    image.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svgString);
  });
}

window.lexiBitmap = async function (id, source, display, dark) {
  try {
    await MathJax.startup.promise;
    const el = renderFormulaSvg(source, display);
    if (el.querySelector('[data-mjx-error]')) throw new Error('Invalid or unsupported LaTeX');
    const svg = el.querySelector('svg');
    const rawWidth = svg.getAttribute('width') || '';
    const minWidth = (svg.style && svg.style.minWidth) ? parseFloat(svg.style.minWidth) : 0;
    const exWidth = rawWidth.endsWith('%')
      ? Math.max((Number.isFinite(minWidth) && minWidth > 0 ? minWidth : 12) + 4, 15)
      : parseFloat(rawWidth);
    const exHeight = parseFloat(svg.getAttribute('height') || '0');
    const width = Math.max(1, exWidth * 8);
    const height = Math.max(1, exHeight * 8);
    if (!Number.isFinite(width) || !Number.isFinite(height) || width > 4096 || height > 2048) throw new Error('Formula exceeds image limits');
    svg.setAttribute('width', String(width));
    svg.setAttribute('height', String(height));
    const fg = dark ? '#f5f3fb' : '#231b36';
    svg.setAttribute('color', fg);
    svg.setAttribute('style', 'color:' + fg);
    const styleEl = document.createElementNS('http://www.w3.org/2000/svg', 'style');
    styleEl.textContent = LEXI_SVG_STYLES;
    svg.insertBefore(styleEl, svg.firstChild);
    const svgString = new XMLSerializer().serializeToString(svg);
    const image = await loadImageFromSvg(svgString);
    const scale = Math.min(2, 4096 / width, 4096 / height);
    const canvas = document.createElement('canvas');
    canvas.width = Math.max(1, Math.ceil(width * scale));
    canvas.height = Math.max(1, Math.ceil(height * scale));
    canvas.getContext('2d').drawImage(image, 0, 0, canvas.width, canvas.height);
    const data = canvas.toDataURL('image/png').split(',')[1];
    window.lexiBitmapBridge.complete(id, JSON.stringify({ width, height, data }));
  } catch (err) {
    window.lexiBitmapBridge.complete(id, '');
  }
};

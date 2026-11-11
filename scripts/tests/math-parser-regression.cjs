// Exercises the real ArkTS math/Markdown parser and source-coordinate editor helpers.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.LEXI_TYPESCRIPT || '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript');
const cache = new Map();
function load(name) {
  if (cache.has(name)) return cache.get(name);
  const file = path.resolve(__dirname, '../../entry/src/main/ets/core', name + '.ets');
  const js = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  const mod = { exports: {} };
  vm.runInThisContext('(function(require,module,exports){' + js + '\n})', { filename: file })(
    spec => load(spec.slice(2)), mod, mod.exports);
  cache.set(name, mod.exports);
  return mod.exports;
}
const { MarkdownEngine: M } = load('MarkdownEngine');
const { LexiMathSyntax: MathSyntax } = load('LexiMathSyntax');
const { LexiLiveMarkdown: Live } = load('LexiLiveMarkdown');
const math = source => M.inlineSpans(source).filter(span => span.kind.startsWith('math'));
const cases = [
  ['all four delimiters preserve LaTeX command bodies and display mode', () => {
    const source = String.raw`中文 $x_i^2$、\(\frac{a}{b}\)、$$\sum_{i=1}^{n}i$$、\[\sqrt{x}\]。`;
    assert.deepEqual(math(source).map(span => [span.kind, span.text]), [
      ['math', 'x_i^2'], ['math', String.raw`\frac{a}{b}`],
      ['math-display', String.raw`\sum_{i=1}^{n}i`], ['math-display', String.raw`\sqrt{x}`]
    ]);
    const tokens = MathSyntax.inlineTokens(source);
    assert.deepEqual(tokens.map(token => source.slice(token.start, token.end)), [
      '$x_i^2$', String.raw`\(\frac{a}{b}\)`, String.raw`$$\sum_{i=1}^{n}i$$`, String.raw`\[\sqrt{x}\]`
    ]);
  }],
  ['subscripts, stars, links and formatting characters in math stay literal', () => {
    const source = String.raw`前 $a_i*b_j + \text{**raw**} + [x](y)$ 后 *强调*`;
    assert.equal(math(source)[0].text, String.raw`a_i*b_j + \text{**raw**} + [x](y)`);
    assert.deepEqual(M.inlineSpans(source).map(span => span.kind), ['text', 'math', 'text', 'italic']);
  }],
  ['surrounding Markdown styles still render on either side of math', () => {
    const spans = M.inlineSpans(String.raw`**结论 $x_i*y_j$ 成立** 和 ==\(z\)==`);
    assert.deepEqual(spans.map(span => [span.kind, span.text]), [
      ['bold', '结论 '], ['math', 'x_i*y_j'], ['bold', ' 成立'], ['text', ' 和 '], ['math', 'z']
    ]);
    assert.equal(new Set(spans.map(span => span.id)).size, spans.length);
  }],
  ['escaped dollars, escaped slash delimiters and currency remain text', () => {
    for (const source of [String.raw`\$x\$`, String.raw`\\(x\\)`, '$5 and $10', '$ x $', '$x $']) {
      assert.equal(math(source).length, 0, source);
    }
    assert.equal(math(String.raw`$a + \$5$`)[0].text, String.raw`a + \$5`);
    assert.equal(math(String.raw`\\$x$`)[0].text, 'x');
    assert.deepEqual(math('$20 and $30 then $x$').map(span => span.text), ['x']);
    assert.deepEqual(math('$x$$y$').map(span => span.text), ['x', 'y']);
  }],
  ['code spans, fenced code and literal link targets do not start math', () => {
    for (const source of ['`$x_i$`', '``$x$``', String.raw`[价格](https://example.com/$x$)`, '[[$target$]]']) {
      assert.equal(math(source).length, 0, source);
    }
    const blocks = M.parseBlocks('```latex\n$$x_i$$\n\\[x\\]\n```\n\n$x$');
    assert.deepEqual(blocks.map(block => block.kind), ['code', 'paragraph']);
    assert.equal(blocks[0].text, '$$x_i$$\n\\[x\\]');
  }],
  ['single-dollar and parenthesis inline math cannot consume the next line', () => {
    assert.equal(math('$x\nnext $').length, 0);
    assert.equal(math('\\(x\nnext\\)').length, 0);
    assert.equal(math('$incomplete').length, 0);
    assert.equal(math('\\(incomplete').length, 0);
  }],
  ['math pipes and LaTeX escaped bars do not split table cells', () => {
    const source = String.raw`| $\left|x\right|$ | \(\begin{array}{c|c}a&b\end{array}\) |`;
    assert.deepEqual(M.splitTableRow(source), [String.raw`$\left|x\right|$`, String.raw`\(\begin{array}{c|c}a&b\end{array}\)`]);
    const blocks = M.parseBlocks(source + '\n| --- | --- |\n| $a|b$ | `x|y` |');
    assert.equal(blocks[0].kind, 'table');
    assert.deepEqual(M.tableData(blocks[0]).rows[1], ['$a|b$', '`x|y`']);
  }],
  ['compact and multiline display formulas retain their first and closing lines', () => {
    const source = '$$x^2$$\n\n$$\\frac{a}{b}\n+ c$$\n\n\\[\\begin{pmatrix}\na&b\\\\\nc&d\n\\end{pmatrix}\\]\n\n后文';
    const blocks = M.parseBlocks(source);
    assert.deepEqual(blocks.map(block => block.kind), ['formula', 'formula', 'formula', 'paragraph']);
    assert.deepEqual(blocks.map(block => block.lineIndex), [0, 2, 5, 10]);
    assert.equal(blocks[1].text, '\\frac{a}{b}\n+ c');
    assert.equal(blocks[2].text, '\\begin{pmatrix}\na&b\\\\\nc&d\n\\end{pmatrix}');
  }],
  ['unclosed display formulas do not discard headings or following text', () => {
    for (const source of ['$$\\frac{a}{b}\n后文\n\n## 保留标题\n继续', '\\[\nx^2\n\n后文']) {
      const blocks = M.parseBlocks(source);
      assert.equal(blocks.some(block => block.kind === 'formula'), false);
      assert.ok(blocks.some(block => block.text === '后文'));
    }
    assert.deepEqual(M.parseBlocks('$$x$$ 后文').map(block => block.kind), ['paragraph']);
    assert.equal(M.parseBlocks('$$x$$ 后文')[0].text, '$$x$$ 后文');
  }],
  ['escaped display closers stay in formula content', () => {
    const blocks = M.parseBlocks('$$\na\\$$ + b\n$$\n后文');
    assert.equal(blocks[0].kind, 'formula');
    assert.equal(blocks[0].text, 'a\\$$ + b');
    assert.equal(blocks[1].text, '后文');
  }],
  ['formula source ranges preserve frontmatter, CRLF and the exact delimiters', () => {
    const formula = '\\[\\frac{a}{b}\r\n+ c\\]';
    const source = '---\r\ntags: [数学]\r\n---\r\n# 前文\r\n\r\n' + formula + '\r\n\r\n后文';
    const blocks = M.parseBlocks(source);
    assert.equal(blocks[1].lineIndex, 5);
    const range = Live.rangeAt(source, source.indexOf('+ c'));
    assert.equal(range.kind, 'formula');
    assert.equal(source.slice(range.start, range.end), formula);
    const replacement = '$$x$$';
    assert.equal(Live.replace(source, range.start, range.end, replacement).content, source.replace(formula, () => replacement));
  }],
  ['live editing advances only after a complete display formula', () => {
    for (const source of ['$$\n', '$$x\n', '\\[\n', '\\[x\n']) {
      assert.equal(Live.shouldAdvance(source, 'paragraph'), false, source);
    }
    for (const source of ['$$x$$\n', '$$\nx\n$$\n', '\\[x\\]\n', '\\[\r\nx\r\n\\]\r\n', '\\begin{align*}\na&=b\n\\end{align*}\n']) {
      assert.equal(Live.shouldAdvance(source, 'formula'), true, source);
    }
    assert.equal(Live.shouldAdvance('$$x$$\nextra\n', 'formula'), false);
  }],
  ['spaced LaTeX inline formulas, nested dollars in braces, raw environments and math fences work', () => {
    assert.deepEqual(math('行内公式 $ \\frac{1}{2} + x_i $ 正常识别').map(span => span.text), [String.raw`\frac{1}{2} + x_i`]);
    assert.deepEqual(math('价格是$5，而公式是$x = 1$').map(span => span.text), ['x = 1']);
    assert.deepEqual(math(String.raw`$\text{当 $x > 0$ 时 } f(x) = x^2$`).map(span => span.text), [String.raw`\text{当 $x > 0$ 时 } f(x) = x^2`]);
    const blocks = M.parseBlocks('```math\n\\int_0^\\infty e^{-x^2}\\dd{x}\n```\n\n\\begin{align*}\na &= b \\\\\nc &= d\n\\end{align*}');
    assert.deepEqual(blocks.map(block => block.kind), ['formula', 'formula']);
  }]
];
for (const [name, run] of cases) { run(); console.log('PASS ' + name); }
console.log(`${cases.length} math parser regression groups passed.`);

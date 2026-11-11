// Exercises the bundled engine itself; LEXI_MATH_BROWSER=1 also checks real DOM/layout.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {pathToFileURL} = require('node:url');
const root = path.resolve(__dirname, '../../entry/src/main/resources/rawfile/lexi-math');
const katex = require(path.join(root, 'katex/katex.min.js'));
const options = {throwOnError:true, strict:'ignore', trust:false, maxExpand:1000, maxSize:20};
const formulas = [
  String.raw`E=mc^2`,
  String.raw`\frac{-b\pm\sqrt{b^2-4ac}}{2a}`,
  String.raw`\sum_{n=1}^{\infty}\frac{1}{n^2}=\frac{\pi^2}{6}`,
  String.raw`\int_0^1 x^2\,dx=\frac13`,
  String.raw`\begin{pmatrix}a&b\\c&d\end{pmatrix}`,
  String.raw`f(x)=\begin{cases}x^2&x\ge0\\-x&x<0\end{cases}`,
  String.raw`\begin{aligned}a&=b+c\\d&=e+f\end{aligned}`,
  String.raw`\left\langle\mathbf{x},\mathbf{y}\right\rangle\in\mathbb{R}`,
  String.raw`\text{面积}=\pi r^2`,
  String.raw`\newcommand{\sq}[1]{#1^2}\sq{x}`
];

for (const source of formulas) {
  const html=katex.renderToString(source,{...options,displayMode:true,macros:{}});
  assert.ok(html.includes('katex-html'), source);
  assert.ok(html.includes('<math'), 'MathML must remain available for accessibility');
  assert.ok(!html.includes('katex-error'), source);
}
console.log(`PASS ${formulas.length} common LaTeX formula families render through bundled KaTeX`);
assert.throws(()=>katex.renderToString(String.raw`\frac{`,options));
assert.throws(()=>katex.renderToString(String.raw`\def\loop{\loop}\loop`,options));
const untrusted=katex.renderToString(String.raw`\href{javascript:alert(1)}{click}`,options);
assert.ok(!untrusted.includes('href='));
console.log('PASS invalid syntax, recursive macros, and untrusted navigation remain bounded');

const css=fs.readFileSync(path.join(root,'katex/katex.min.css'),'utf8');
const fontPaths=[...css.matchAll(/url\(([^)]+)\)/g)].map(match=>match[1].replace(/["']/g,''));
assert.equal(fontPaths.length,20);
for(const file of fontPaths) assert.ok(fs.existsSync(path.join(root,'katex',file)),file);
for(const name of ['renderer.html','renderer.css','renderer.js']) assert.ok(fs.existsSync(path.join(root,name)));
console.log('PASS all offline styles, scripts, and referenced WOFF2 fonts are bundled');

async function browserChecks() {
  const playwright=require(process.env.LEXI_PLAYWRIGHT || '/Applications/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/playwright');
  const browser=await playwright.chromium.launch({headless:true,executablePath:process.env.LEXI_CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
  try {
    const page=await browser.newPage({viewport:{width:320,height:700}});
    const errors=[]; const network=[]; const failures=[];
    page.on('pageerror',error=>errors.push(error.message));
    page.on('request',request=>{if(/^https?:/.test(request.url())) network.push(request.url());});
    page.on('requestfailed',request=>failures.push(request.url()+': '+request.failure().errorText));
    await page.goto(pathToFileURL(path.join(root,'renderer.html')).href);
    const initialURL=page.url();
    await page.evaluate(()=>{
      window.bridgeCalls=[];
      window.resizeCalls=[];
      window.lexiMathBridge={edit:()=>window.bridgeCalls.push(['edit']),activate:id=>window.bridgeCalls.push(['activate',id]),resize:height=>window.resizeCalls.push(height)};
    });
    const payload={spans:formulas.map((text,index)=>({id:'m'+index,kind:'math-display',text})),textSize:16,textLeading:27};
    await page.evaluate(payload=>window.lexiRender(payload),payload);
    await page.evaluate(()=>document.fonts.ready);
    assert.equal(await page.locator('.katex').count(),formulas.length);
    assert.equal(await page.locator('.math-error').count(),0);
    assert.equal(await page.locator('.katex-mathml math').count(),formulas.length);
    assert.ok(await page.evaluate(()=>document.fonts.check('16px KaTeX_Main')));
    assert.ok(await page.evaluate(()=>document.body.scrollHeight>300));
    assert.ok(await page.evaluate(()=>window.resizeCalls.some(height=>height>300)), 'content height must reach the native view');
    console.log('PASS browser loads offline engine/fonts and lays out matrices, fractions, and multiline equations');

    await page.evaluate(()=>window.lexiRender({spans:[
      {id:'plain',kind:'text',text:'中文与 <img src=x onerror=alert(1)> '},
      {id:'bad',kind:'math',text:'\\frac{'},
      {id:'good',kind:'math',text:'x^2'},
      {id:'link',kind:'url',text:'参考链接',target:'javascript:alert(1)'},
      {id:'bold',kind:'bold',text:'加粗'},
      {id:'code',kind:'code',text:'$literal$'}
    ],textSize:16,textLeading:27,dark:true}));
    assert.equal(await page.locator('img').count(),0);
    assert.equal(await page.locator('.math-error').textContent(),String.raw`\frac{`);
    assert.equal(await page.locator('.katex').count(),1);
    assert.equal(await page.locator('.bold').textContent(),'加粗');
    assert.equal(await page.locator('.code').textContent(),'$literal$');
    assert.equal(await page.locator('a[href]').count(),0);
    assert.equal(await page.evaluate(()=>getComputedStyle(document.body).color),'rgb(245, 243, 251)');
    await page.getByRole('link',{name:'参考链接'}).click();
    assert.deepEqual(await page.evaluate(()=>window.bridgeCalls),[['activate','link']]);
    assert.equal(page.url(),initialURL);
    await page.locator('.bold').click();
    assert.deepEqual(await page.evaluate(()=>window.bridgeCalls),[['activate','link'],['edit']]);
    console.log('PASS source remains text, malformed formula preserves neighbors, theme and native link/edit bridge work');

    await page.evaluate(()=>{
      window.bridgeCalls=[];
      window.lexiRender({spans:[{id:'long',kind:'math',text:Array(45).fill('x_{123}').join('+')}],displayMode:true,textSize:18,textLeading:28});
    });
    const long=await page.locator('.math-display').evaluate(element=>({width:element.clientWidth,scroll:element.scrollWidth,body:document.documentElement.scrollWidth}));
    assert.ok(long.scroll>long.width*2,JSON.stringify(long));
    assert.ok(long.body<=320,JSON.stringify(long));
    await page.locator('.math-display').evaluate(element=>{
      element.dispatchEvent(new PointerEvent('pointerdown',{bubbles:true,clientX:100,clientY:30}));
      element.dispatchEvent(new PointerEvent('pointermove',{bubbles:true,clientX:140,clientY:30}));
      element.dispatchEvent(new MouseEvent('click',{bubbles:true}));
    });
    assert.deepEqual(await page.evaluate(()=>window.bridgeCalls),[]);
    await page.locator('.math-display').evaluate(element=>{
      const selection=window.getSelection();
      const range=document.createRange(); range.selectNodeContents(element); selection.removeAllRanges(); selection.addRange(range);
      element.dispatchEvent(new PointerEvent('pointerdown',{bubbles:true,clientX:100,clientY:30}));
      element.dispatchEvent(new MouseEvent('click',{bubbles:true}));
    });
    assert.deepEqual(await page.evaluate(()=>window.bridgeCalls),[]);
    await page.setViewportSize({width:1000,height:700});
    assert.ok(await page.locator('.math-display').evaluate(element=>element.clientWidth===1000));
    assert.deepEqual(network,[]); assert.deepEqual(failures,[]); assert.deepEqual(errors,[]);
    console.log('PASS long equations scroll within the view, dragging/selection do not edit, and resizing does not overflow');
    if(process.env.LEXI_MATH_SCREENSHOT) await page.screenshot({path:process.env.LEXI_MATH_SCREENSHOT,fullPage:true});
  } finally { await browser.close(); }
}

if(process.env.LEXI_MATH_BROWSER==='1') browserChecks().catch(error=>{console.error(error);process.exitCode=1;});

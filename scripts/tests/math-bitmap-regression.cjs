const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const crypto=require('node:crypto');
const path=require('node:path');
const ts=require(process.env.LEXI_TYPESCRIPT||'/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript');
const source=fs.readFileSync(path.resolve(__dirname,'../../entry/src/main/ets/core/LexiMathBitmapCache.ets'),'utf8');
const js=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2021}}).outputText;
const files=new Map(); let renders=[];
const fakefs={OpenMode:{CREATE:1,READ_WRITE:2,TRUNC:4},readText:async p=>{if(!files.has(p)) throw Error('missing');return files.get(p)},mkdir:async()=>{},open:async p=>({fd:p}),write:async (p,s)=>{files.set(p,s)},close:async()=>{}};
const fakecrypto={createMd:()=>{let h=crypto.createHash('sha256');return{updateSync:b=>h.update(b.data),digestSync:()=>({data:h.digest()})}}};
const fakeutil={TextEncoder:class {encodeInto(s){return new TextEncoder().encode(s)}}};
function runtime(){const mod={exports:{}};vm.runInNewContext('(function(require,module,exports,AppStorage,setTimeout,clearTimeout){'+js+'\n})')(
 name=>name==='@kit.CoreFileKit'?{fileIo:fakefs}:name==='@kit.CryptoArchitectureKit'?{cryptoFramework:fakecrypto}:name==='@kit.ArkTS'?{util:fakeutil}:{},mod,mod.exports,{setOrCreate(){}},setTimeout,clearTimeout);return mod.exports.LexiMathBitmapCache}
const tick=()=>new Promise(r=>setTimeout(r,10));
(async()=>{const c=runtime();const context={filesDir:'/app'};const outputs=[];c.register({runJavaScript:async s=>{renders.push(s)}});c.request(context,'x^2',false,false,x=>outputs.push(x));c.request(context,'x^2',false,false,x=>outputs.push(x));await tick();assert.equal(renders.length,1,'identical formulas share a render');const key=/window\.lexiBitmap\("([a-f0-9]+)"/.exec(renders[0])[1];c.complete(key,JSON.stringify({width:20,height:12,data:'abc'}));await tick();assert.equal(outputs.length,2);assert.equal(files.size,1);const d=runtime();const restored=[];d.request(context,'x^2',false,false,x=>restored.push(x));await tick();assert.equal(restored[0].data,'abc');assert.equal(renders.length,1,'restart reads disk without renderer');const dark=[];d.register({runJavaScript:async s=>{renders.push(s)}});d.request(context,'x^2',false,true,x=>dark.push(x));await tick();assert.equal(renders.length,2,'theme gets a distinct cache key');const darkKey=/window\.lexiBitmap\("([a-f0-9]+)"/.exec(renders[1])[1];d.complete(darkKey,'');await tick();assert.equal(dark[0],undefined,'errors fall back without caching');console.log('PASS background queue, deduplication, persistence across restart, theme invalidation and failed rendering');})().catch(e=>{console.error(e);process.exitCode=1});

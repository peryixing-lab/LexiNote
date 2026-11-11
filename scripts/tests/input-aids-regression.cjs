const assert=require('node:assert/strict'), fs=require('node:fs'), vm=require('node:vm');
const ts=require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript');
function load(name,requireFn=()=>({})){const exports={};vm.runInNewContext(ts.transpileModule(fs.readFileSync('entry/src/main/ets/core/'+name+'.ets','utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2021}}).outputText,{exports,require:requireFn});return exports;}
const multi=load('LexiMultiCaret').LexiMultiCaret;
let result=multi.insert('a\nb\nc',[1,3,5],'!');assert.equal(result.content,'a!\nb!\nc!');assert.equal(result.carets.join(','),'2,5,8');
result=multi.remove(result.content,Array.from(result.carets),true,1);assert.equal(result.content,'a\nb\nc');
assert.equal(multi.insert('abc',[1,1],'x').content,'axbc');
assert.equal(multi.remove('abcdef',[2,3],true,2).content,'def');
assert.equal(multi.remove('😀x\n😀y',[2,6],true,1).content,'x\ny');
const spell=load('LexiSpellcheck',()=>({util:{TextDecoder:{create:()=>({decodeToString:bytes=>Buffer.from(bytes).toString('utf8')})}}})).LexiSpellcheck;
(async()=>{const context={resourceManager:{getRawFileContent:async()=>new Uint8Array(fs.readFileSync('entry/src/main/resources/rawfile/lexinote_spell_en.txt'))}};
const issues=await spell.check(context,'hello world teh qzxxyz `qzxcode` https://qzxurl.test');
assert.equal(issues.some(issue=>issue.word==='hello'),false);assert.ok(issues.find(issue=>issue.word==='teh').suggestions.includes('the'));
assert.ok(issues.some(issue=>issue.word==='qzxxyz'));assert.equal(issues.some(issue=>issue.word==='qzxcode'||issue.word==='qzxurl'),false);
console.log('PASS multicursor insertion/deletion, overlaps, duplicate positions, Unicode boundaries and offline spelling with suggestions');
})().catch(error=>{console.error(error);process.exitCode=1;});

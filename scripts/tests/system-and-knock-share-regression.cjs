// System ShareController file sharing and HarmonyShare knockShare/dataReceive regression checks.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const ts = require(process.env.LEXI_TYPESCRIPT || '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript');
const core = path.resolve(__dirname, '../../entry/src/main/ets/core');

const files = new Map();
const dirs = new Set();
const handles = new Map();
const notes = new Map();
const appStorage = new Map();
let deviceType = 'phone';
let shareControllerCalls = [];
let knockShareRegistrations = [];
let dataReceiveRegistrations = [];
let rejectAnchor = false;
let decodedSize, releasedImages = 0;

const FakeAppStorage = {
  setOrCreate(k, v) { appStorage.set(k, v); },
  set(k, v) { appStorage.set(k, v); },
  get(k) { return appStorage.get(k); }
};

class FakeLocalStorage {
  constructor() { this.values = new Map(); }
  setOrCreate(k, v) { this.values.set(k, v); }
  set(k, v) { this.values.set(k, v); }
  get(k) { return this.values.get(k); }
}

const nativeFs = {
  accessSync: p => files.has(p) || dirs.has(p),
  mkdirSync: p => dirs.add(p),
  statSync: p => ({ size: Buffer.byteLength(files.get(p) || '') }),
  readTextSync: p => files.get(p),
  OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 },
  openSync(p) {
    const fd = handles.size + 1;
    handles.set(fd, p);
    return { fd };
  },
  writeSync(fd, text) { files.set(handles.get(fd), text); },
  fsyncSync() {},
  closeSync() {},
  renameSync(a, b) { files.set(b, files.get(a)); files.delete(a); },
  unlinkSync: p => files.delete(p)
};

class FakeSharedData {
  constructor(record) {
    if (record.utd === 'general.markdown' && !record.content) { throw Object.assign(new Error('Parameter error'), {code:401}); }
    this.records = [record];
  }
  addRecord(record) {
    this.records.push(record);
  }
  getRecords() {
    return this.records;
  }
}

class FakeShareController {
  constructor(data) {
    this.data = data;
  }
  async show(context, options) {
    shareControllerCalls.push({ context, data: this.data, options });
    assert.equal(typeof options.anchor,'object','desktop sharing must not use a string or missing anchor');
    if (rejectAnchor && options.anchor.windowOffset.x===240) { throw Object.assign(new Error('Parameter error'), {code:401}); }
  }
}

const fakeHarmonyShare = {
  SharableErrorCode: { NO_CONTENT_ERROR: 1 },
  ReceivableErrorCode: { NO_RECEIVABLE_ERROR: 1 },
  on(event, arg2, arg3) {
    if (event === 'knockShare') {
      const hasWindow = typeof arg3 === 'function';
      knockShareRegistrations.push({
        action: 'on',
        capability: hasWindow ? arg2 : undefined,
        callback: hasWindow ? arg3 : arg2
      });
    } else if (event === 'dataReceive') {
      dataReceiveRegistrations.push({
        action: 'on',
        capability: arg2,
        callback: arg3
      });
    }
  },
  off(event, arg2, arg3) {
    if (event === 'knockShare') {
      const hasWindow = typeof arg3 === 'function' || (arg2 && typeof arg2 === 'object');
      knockShareRegistrations.push({
        action: 'off',
        capability: hasWindow ? arg2 : undefined,
        callback: typeof arg3 === 'function' ? arg3 : (typeof arg2 === 'function' ? arg2 : undefined)
      });
    } else if (event === 'dataReceive') {
      dataReceiveRegistrations.push({
        action: 'off',
        capability: arg2,
        callback: arg3
      });
    }
  }
};

const store = {
  async init() {},
  async flushPendingWrites() {},
  async getNoteById(id) {
    return notes.has(id) ? JSON.parse(JSON.stringify(notes.get(id))) : undefined;
  },
  async getNoteFileUri(note) { return 'file://docs' + note.path; },
  async getActiveFolderUri() { return 'file://docs/documents/工作区'; }
};

const cache = new Map();
function load(name) {
  if (cache.has(name)) return cache.get(name);
  const source = fs.readFileSync(path.join(core, name + '.ets'), 'utf8');
  const js = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  const module = { exports: {} };
  cache.set(name, module.exports);
  const req = spec => {
    if (spec === '@kit.ImageKit') return {image:{createImageSource:()=>({createPixelMap:async options=>{decodedSize=options.desiredSize;return {release:async()=>releasedImages++};},release:async()=>releasedImages++}),createImagePacker:()=>({packToData:async()=>new ArrayBuffer(256),release:async()=>releasedImages++})}};
    if (spec === '@kit.PerformanceAnalysisKit') return {hilog:{info(){},error(){}}};
    if (spec === './LexiStorageService') return { LexiStorageService: store };
    if (spec.startsWith('./')) return load(spec.slice(2));
    if (spec === '@kit.ArkTS') return {
      url: { URL: { parseURL: s => new URL(s) } },
      util: { generateRandomUUID: () => crypto.randomUUID() }
    };
    if (spec === '@kit.CoreFileKit') return {
      fileIo: nativeFs,
      fileUri: { getUriFromPath: p => 'file://com.lovexjy.lexinote' + p }
    };
    if (spec === '@kit.BasicServicesKit') return {
      deviceInfo: {
        get deviceType() { return deviceType; },
        apiAvailable: () => true
      }
    };
    if (spec === '@kit.ShareKit') return {
      systemShare: {
        SharedData: FakeSharedData,
        ShareController: FakeShareController,
        SharePreviewMode: { DEFAULT: 0, DETAIL: 1 },
        SelectionMode: { SINGLE: 0, BATCH: 1 }
      },
      harmonyShare: fakeHarmonyShare
    };
    if (spec === '@kit.ArkData') return {
      uniformTypeDescriptor: {
        UniformDataType: {
          MARKDOWN: 'general.markdown',
          PLAIN_TEXT: 'general.plain-text',
          FILE: 'general.file',
          TEXT: 'general.text'
        },
        getUniformDataTypeByFilenameExtension(ext) {
          return ext === '.md' ? 'general.markdown' : '';
        }
      }
    };
    if (spec === '@kit.ArkUI') return {window:{getLastWindow:async()=>({getWindowProperties:()=>({windowRect:{width:800,height:600}}),getUIContext:()=>({vp2px:n=>n*2,getAttachedFrameNodeById:()=>({isAttached:()=>true,isVisible:()=>true,getPositionToWindow:()=>({x:120,y:80}),getMeasuredSize:()=>({width:44,height:44})})})})}};
    if (spec === '@kit.AbilityKit') return {
      AbilityConstant: { ContinueState: { ACTIVE: 0, INACTIVE: 1 } }
    };
    throw new Error('Unexpected import: ' + spec);
  };
  const canIUse = cap => cap === 'SystemCapability.Collaboration.HarmonyShare';
  vm.runInThisContext('(function(require,module,exports,AppStorage,LocalStorage,canIUse,$r){' + js + '\n})', { filename: name })(
    req, module, module.exports, FakeAppStorage, FakeLocalStorage, canIUse, () => ({id:1})
  );
  cache.set(name, module.exports);
  return module.exports;
}

const { LexiShareService } = load('LexiShareService');
const { LexiContinuationSession } = load('LexiContinuationSession');
const { LexiContinuationDraft } = load('LexiContinuationData');
const { NoteItem } = load('LexiModels');
const { LexiContextTarget, LexiContextBridge } = load('LexiContextModels');

const context = {
  filesDir: '/sandbox/files',
  cacheDir: '/sandbox/cache',
  abilityInfo: { name: 'EntryAbility' },
  setMissionContinueState: async () => {}
};

function reset() {
  files.clear();
  dirs.clear();
  handles.clear();
  notes.clear();
  appStorage.clear();
  deviceType = 'phone';
  shareControllerCalls = [];
  knockShareRegistrations = [];
  dataReceiveRegistrations = [];
  rejectAnchor = false;
  decodedSize=undefined;releasedImages=0;LexiShareService.previewBytes=undefined;
  LexiContinuationSession.owner = '';
  LexiContinuationSession.getter = undefined;
  LexiShareService.activeOwner = '';
  LexiShareService.activeGetter = undefined;
  LexiShareService.windowBindings = new Map();
}

const tests = [
  ['sanitizeFileName strips illegal filesystem characters and defaults empty titles', async () => {
    assert.equal(LexiShareService.sanitizeFileName('  我的:笔记/草稿?*<>|  '), '我的_笔记_草稿.md');
    assert.equal(LexiShareService.sanitizeFileName('...'), '未命名笔记.md');
  }],
  ['shareNoteById shares a sandbox copy with FILE UTD and keeps the workspace original untouched', async () => {
    const n = new NoteItem();
    n.id = 'note-share-1';
    n.title = '分布式架构笔记';
    n.content = '# 分布式架构笔记\n\n支持系统文件分享与碰一碰。\n';
    n.notebook = '研发笔记';
    n.path = '/documents/知萤/分布式架构笔记.md';
    files.set(n.path, n.content);
    notes.set(n.id, n);

    await LexiShareService.shareNoteById(context, n.id, 'context-trigger-note-note-share-1');
    assert.equal(shareControllerCalls.length, 1);
    const call = shareControllerCalls[0];
    assert.deepEqual(call.options.anchor, {windowOffset:{x:240,y:160},size:{width:44,height:44}});
    assert.equal(call.options.previewMode, 0);
    assert.equal(call.options.selectionMode, 0);

    const records = call.data.getRecords();
    assert.equal(records.length, 1);
    assert.equal(records[0].utd, 'general.file');
    assert.equal(records[0].title, '分布式架构笔记.md');
    assert.equal(records[0].uri, 'file://com.lovexjy.lexinote/sandbox/cache/lexi-share/分布式架构笔记.md');
    assert.equal(files.get(n.path), n.content);
    assert.ok(files.get('/sandbox/cache/lexi-share/分布式架构笔记.md').includes(n.content));
    assert.equal(files.size,2);
  }],
  ['a detached share anchor retries at the default location', async () => {
    const n=new NoteItem();n.id='anchor-note';n.title='定位';n.path='/documents/定位.md';n.content='内容';notes.set(n.id,n);files.set(n.path,n.content);rejectAnchor=true;
    await LexiShareService.shareNoteById(context,n.id,'detached-trigger');
    assert.equal(shareControllerCalls.length,2);assert.deepEqual(shareControllerCalls[1].options.anchor,{windowOffset:{x:400,y:300}});
  }],
  ['large Markdown bodies never enter the IPC record', async () => {
    const n=new NoteItem();n.id='large-file';n.title='大文件';n.path='/documents/large.md';n.content='正文'.repeat(600000);notes.set(n.id,n);files.set(n.path,n.content);
    await LexiShareService.shareNoteById(context,n.id);const record=shareControllerCalls[0].data.getRecords()[0];
    assert.equal(record.content,undefined);assert.equal(record.thumbnail,undefined);assert.ok(JSON.stringify(record).length<1000);assert.equal(files.size,2);
  }],
  ['large app artwork is decoded to a small preview before Share Kit serialization', async () => {
    const n=new NoteItem();n.id='preview';n.path='/documents/preview.md';notes.set(n.id,n);files.set(n.path,'正文');
    const previewContext={...context,resourceManager:{getMediaContentSync:()=>new Uint8Array(18728)}};
    await LexiShareService.shareNoteById(previewContext,n.id);const record=shareControllerCalls[0].data.getRecords()[0];
    assert.deepEqual(decodedSize,{width:32,height:32});assert.equal(record.thumbnail.length,256);assert.ok(JSON.stringify(record).length<16384);assert.equal(releasedImages,3);
  }],
  ['sharing refuses a private or unsaved file without creating a Markdown cache', async () => {
    const n=new NoteItem();n.id='private';n.path='/sandbox/files/private.md';notes.set(n.id,n);files.set(n.path,'保留');
    await assert.rejects(LexiShareService.shareNoteById(context,n.id),/本地工作区/);assert.equal(files.size,1);assert.equal(shareControllerCalls.length,0);
  }],
  ['context menu for note includes share-file action', async () => {
    const n = new NoteItem();
    n.id = 'note-ctx';
    n.title = '测试菜单';
    const actions = LexiContextBridge.actions(LexiContextTarget.note(n), true);
    assert.ok(actions.some(a => a.id === 'share-file' && a.label === '系统分享文件'));
  }],
  ['knockShare shares active editor note from LexiContinuationSession with file URI and coordinate', async () => {
    const n=new NoteItem();n.id='note-knock-1';n.path='/documents/碰一碰跨端笔记.md';n.content='# 碰一碰跨端笔记\n\n正在编辑的正文内容\n';notes.set(n.id,n);files.set(n.path,n.content);
    const owner = LexiContinuationSession.newOwner();
    LexiContinuationSession.activate(context, owner, () => {
      const draft = new LexiContinuationDraft();
      draft.sourceNoteId = 'note-knock-1';
      draft.title = '碰一碰跨端笔记';
      draft.content = '# 碰一碰跨端笔记\n\n正在编辑的正文内容\n';
      return draft;
    });

    let sharedPayload;
    let clarified;
    await LexiShareService.handleKnockShare(context, {
      getInfo: () => ({ coordinate: { screenX: 180, screenY: 60 } }),
      async share(data) { sharedPayload = data; },
      async clarifyNonShare(info) { clarified = info; }
    });

    assert.equal(clarified, undefined);
    assert.ok(sharedPayload);
    const records = sharedPayload.getRecords();
    assert.equal(records[0].title, '碰一碰跨端笔记.md');
    assert.equal(records[0].uri,'file://com.lovexjy.lexinote/sandbox/cache/lexi-share/碰一碰跨端笔记.md');assert.equal(files.size,2);
  }],
  ['knockShare calls clarifyNonShare when no note is open in editor', async () => {
    let sharedPayload;
    let clarified;
    LexiShareService.handleKnockShare(context, {
      async share(data) { sharedPayload = data; },
      async clarifyNonShare(info) { clarified = info; }
    });
    assert.equal(sharedPayload, undefined);
    assert.ok(clarified && clarified.message.includes('先打开一篇笔记'));
  }],
  ['window registration supports outgoing knockShare and leaves incoming files with the system', async () => {
    const fakeWindow = { getWindowProperties: () => ({ id: 42 }) };
    deviceType = 'phone';
    LexiShareService.registerWindow('EntryAbility', context, fakeWindow);
    assert.equal(knockShareRegistrations.length, 1);
    assert.equal(knockShareRegistrations[0].capability, undefined);
    assert.equal(dataReceiveRegistrations.length, 0);
    LexiShareService.unregisterWindow('EntryAbility');
    assert.equal(knockShareRegistrations.length, 2);
    assert.equal(knockShareRegistrations[1].action, 'off');

    knockShareRegistrations = [];
    dataReceiveRegistrations = [];
    deviceType = '2in1';
    LexiShareService.registerWindow('EntryAbility', context, fakeWindow);
    assert.equal(knockShareRegistrations.length, 1);
    assert.deepEqual(knockShareRegistrations[0].capability, { windowId: 42 });
    assert.equal(dataReceiveRegistrations.length, 0, 'system owns incoming files; no app sandbox receiver');

    LexiShareService.unregisterWindow('EntryAbility');
    assert.equal(knockShareRegistrations[1].action, 'off');
  }]
];

(async () => {
  for (const [name, run] of tests) {
    reset();
    await run();
    console.log('PASS ' + name);
  }
  console.log(`${tests.length} system and knock share regression groups passed`);
})().catch(e => {
  console.error(e);
  process.exitCode = 1;
});

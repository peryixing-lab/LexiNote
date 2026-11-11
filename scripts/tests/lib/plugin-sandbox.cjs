// Shared sandbox for plugin-* regressions.
//
// It transpiles the real .ets sources with the DevEco bundled TypeScript and executes them
// against an in-memory file system, RDB and preferences implementation. Nothing here replaces
// device verification: ArkWeb, ArkUI and real signing still need a device/emulator.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const ts = require(process.env.LEXI_TYPESCRIPT ||
  '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript');

const ETS_ROOT = path.resolve(__dirname, '../../../entry/src/main/ets');

function createSandbox() {
  const state = {
    noteRows: new Map(), contentRows: new Map(), linkRows: [], sqlCalls: [], insertCalls: [],
    nativeLocks: new Map(), files: new Map(), values: new Map(), handles: new Map(),
    directories: new Set(), symlinks: new Map(), persistentGrants: new Set(), prefs: new Map(),
    appStorage: new Map(), pickerCalls: [], pickerSelection: async () => [], fixedUuids: [],
    httpRequests: [], httpResponses: [],
    failInsert: undefined, db: undefined
  };

  function fileStat(p) {
    if (!state.files.has(p) && !state.directories.has(p) && !state.symlinks.has(p)) throw new Error('ENOENT ' + p);
    return {
      size: Buffer.byteLength(state.files.get(p) || ''), mtime: Date.now() / 1000,
      isDirectory: () => state.directories.has(p),
      isFile: () => state.files.has(p) && !state.symlinks.has(p),
      isSymbolicLink: () => state.symlinks.has(p)
    };
  }

  const fakeFs = {
    accessSync: (p) => state.files.has(p) || state.directories.has(p) || state.symlinks.has(p),
    mkdirSync(p) {
      const parts = p.split('/');
      for (let i = 1; i <= parts.length; i++) { state.directories.add(parts.slice(0, i).join('/') || '/'); }
    },
    async mkdir(p) { fakeFs.mkdirSync(p); },
    stat: async (p) => fileStat(p), lstat: async (p) => fileStat(p),
    statSync: fileStat, lstatSync: fileStat,
    readText: async (p) => state.files.get(p),
    async listFile(p) {
      return [...new Set([...state.files.keys(), ...state.directories, ...state.symlinks.keys()]
        .filter((x) => x.startsWith(p + '/') && x !== p).map((x) => x.slice(p.length + 1).split('/')[0]))];
    },
    openSync(p) {
      const fd = state.handles.size + 1; state.handles.set(fd, p);
      if (!p.endsWith('/lexinote-mutation.lock')) state.files.set(p, '');
      return {
        fd,
        tryLock() {
          if (state.nativeLocks.has(p)) throw Object.assign(new Error('busy'), { code: 13900034 });
          state.nativeLocks.set(p, fd);
        },
        unlock() { state.nativeLocks.delete(p); }
      };
    },
    writeSync(fd, text) { state.files.set(state.handles.get(fd), text); return Buffer.byteLength(text); },
    fsyncSync() {},
    closeSync(file) {
      if (state.nativeLocks.get(state.handles.get(file.fd)) === file.fd) state.nativeLocks.delete(state.handles.get(file.fd));
    },
    readTextSync: (p) => state.files.get(p),
    renameSync(from, to) { state.files.set(to, state.files.get(from)); state.files.delete(from); },
    unlinkSync(p) { state.files.delete(p); },
    OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4, READ_WRITE: 8 }
  };

  const db = {
    version: 0,
    async querySql(sql, args = []) {
      let data = [];
      if (sql.includes('FROM notes_meta')) {
        data = [...state.noteRows.values()]
          .filter((row) => sql.includes('notes_meta.id = ?') ? row.id === args[0] :
            sql.includes('vault_id = ?') ? row.vault_id === args[0] : true)
          .map((row) => [row.metadata_json, (state.contentRows.get(row.id) || {}).content || '']);
      } else {
        const val = state.values.get(args[0]);
        if (val !== undefined) data = [[val]];
      }
      let cursor = -1;
      return {
        goToFirstRow: () => { cursor = 0; return data.length > 0; },
        goToNextRow: () => ++cursor < data.length,
        getString: (i) => data[cursor][i],
        close() {}
      };
    },
    async insert(table, row) {
      await new Promise((resolve) => setTimeout(resolve, 0));
      state.insertCalls.push({ table, row: structuredClone(row) });
      if (table === state.failInsert || (table === 'kv_store' && row.key === state.failInsert)) throw new Error('RDB failure');
      if (table === 'kv_store') state.values.set(row.key, row.value);
      else if (table === 'notes_meta') state.noteRows.set(row.id, structuredClone(row));
      else if (table === 'notes_content') state.contentRows.set(row.id, structuredClone(row));
      else if (table === 'link_index') state.linkRows.push(structuredClone(row));
    },
    async executeSql(sql, args = []) {
      state.sqlCalls.push({ sql, args });
      if (sql === 'DELETE FROM notes_meta') state.noteRows.clear();
      else if (sql === 'DELETE FROM notes_content') state.contentRows.clear();
      else if (sql === 'DELETE FROM link_index') state.linkRows = [];
      else if (sql === 'DELETE FROM link_index WHERE source_id = ?') state.linkRows = state.linkRows.filter((r) => r.source_id !== args[0]);
      else if (sql === 'DELETE FROM kv_store WHERE key = ?') state.values.delete(args[0]);
    },
    async beginTransaction() { state.snapshot = { values: new Map(state.values), noteRows: new Map(state.noteRows), contentRows: new Map(state.contentRows), linkRows: structuredClone(state.linkRows) }; },
    async commit() { state.snapshot = undefined; },
    async rollBack() {
      if (!state.snapshot) return;
      state.values = new Map(state.snapshot.values); state.noteRows = new Map(state.snapshot.noteRows);
      state.contentRows = new Map(state.snapshot.contentRows); state.linkRows = structuredClone(state.snapshot.linkRows);
      state.snapshot = undefined;
    }
  };
  state.db = db;

  const fakePicker = {
    DocumentSelectMode: { FOLDER: 1, FILE: 1 },
    DocumentSelectOptions: class {},
    DocumentViewPicker: class {
      async select(options) { state.pickerCalls.push(options); return state.pickerSelection(options); }
    }
  };
  const fakeFileShare = {
    OperationMode: { READ_MODE: 1, WRITE_MODE: 2, CREATE_MODE: 4, DELETE_MODE: 8, RENAME_MODE: 16 },
    async persistPermission(policies) { for (const p of policies) state.persistentGrants.add(p.uri); },
    async activatePermission(policies) {
      for (const p of policies) if (!state.persistentGrants.has(p.uri)) throw new Error('authorization revoked');
    }
  };
  class FakeFileUri {
    constructor(uri) { this.path = uri.startsWith('file:') ? decodeURIComponent(new URL(uri).pathname) : uri; }
  }

  const kitMocks = {
    '@kit.CoreFileKit': {
      fileIo: fakeFs, picker: fakePicker, fileShare: fakeFileShare,
      Environment: { getUserDocumentDir: () => '/user/Documents' },
      fileUri: { FileUri: FakeFileUri, getUriFromPath: (p) => 'file://docs' + p }
    },
    '@kit.ArkData': {
      relationalStore: { ConflictResolution: { ON_CONFLICT_REPLACE: 1 }, SecurityLevel: { S2: 2 }, getRdbStore: async () => db },
      preferences: { removePreferencesFromCacheSync() {}, getPreferences: async () => sandbox.settings }
    },
    '@kit.ArkTS': { util: { generateRandomUUID: () => state.fixedUuids.length ? state.fixedUuids.shift() : crypto.randomUUID(), TextEncoder: class { encodeInto(text) { return Buffer.from(text, 'utf8'); } } } },
    '@kit.AbilityKit': { common: {}, bundleManager: {}, wantConstant: {} },
    '@kit.BasicServicesKit': { pasteboard: { getSystemPasteboard: () => ({ setData: async () => {} }), createData: () => ({}) } },
    '@kit.FormKit': { formBindingData: { createFormBindingData: (data) => data }, formProvider: { getPublishedRunningFormInfos: async () => [] } },
    '@kit.PerformanceAnalysisKit': { hilog: { warn() {}, info() {}, error() {}, debug() {} } },
    '@kit.ArkUI': { promptAction: {} },
    '@kit.ArkWeb': { webview: { WebviewController: class {} } },
    '@kit.CryptoArchitectureKit': { cryptoFramework: { createMd: () => ({ updateSync() {}, digestSync: () => ({ data: new Uint8Array([0]) }) }) } },
    '@kit.NetworkKit': {
      http: {
        RequestMethod: { POST: 'POST', GET: 'GET' },
        HttpDataType: { STRING: 0, ARRAY_BUFFER: 1 },
        createHttp: () => ({
          async request(url, options) {
            state.httpRequests.push({ url, options });
            const next = state.httpResponses.shift();
            if (!next) { throw new Error('no scripted HTTP response'); }
            if (next.throws) { throw new Error(next.throws); }
            return { responseCode: next.status || 200, result: next.body === undefined ? '' : next.body };
          },
          async requestInStream() { return 200; },
          on() {}, off() {}, destroy() {}
        })
      }
    }
  };

  const cache = new Map();
  const overrides = new Map();

  function resolveSpec(spec, fromFile) {
    const baseDir = fromFile ? path.posix.dirname(fromFile) : '';
    const joined = path.posix.normalize(path.posix.join(baseDir, spec));
    return joined.replace(/\.ets$/, '');
  }

  function loadFile(id) {
    const key = id.replace(/\.ets$/, '');
    if (overrides.has(key)) return overrides.get(key);
    if (cache.has(key)) return cache.get(key);
    const filename = path.join(ETS_ROOT, key + '.ets');
    const source = fs.readFileSync(filename, 'utf8');
    const js = ts.transpileModule(source, {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
    }).outputText;
    const moduleExports = {};
    cache.set(key, moduleExports);
    const req = (spec) => {
      if (kitMocks[spec]) return kitMocks[spec];
      if (spec.startsWith('@kit.')) throw new Error('Unhandled kit import: ' + spec);
      return loadFile(resolveSpec(spec, key + '.ets'));
    };
    vm.runInThisContext('(function(require,module,exports){' + js + '\n})', { filename })(req, { exports: moduleExports }, moduleExports);
    return moduleExports;
  }

  const sandbox = {
    state,
    fakeFs,
    db,
    settings: { get: async (k, fallback) => state.prefs.has(k) ? state.prefs.get(k) : fallback, put: async (k, v) => state.prefs.set(k, v), flush: async () => {} },
    load: loadFile,
    override(id, value) { overrides.set(id.replace(/\.ets$/, ''), value); },
    /** Queues one HTTP result for PluginAiService: `{ status, body }` or `{ throws }`. */
    expectHttp(value) { state.httpResponses.push(value); },
    contexts: { filesDir: '/sandbox/files', getApplicationContext() { return this; } },
    reset() {
      state.noteRows = new Map(); state.contentRows = new Map(); state.linkRows = [];
      state.sqlCalls = []; state.insertCalls = []; state.nativeLocks = new Map();
      state.files = new Map(); state.values = new Map(); state.handles = new Map();
      state.directories = new Set(); state.symlinks = new Map(); state.persistentGrants = new Set();
      state.prefs = new Map(); state.appStorage = new Map();
      state.pickerCalls = []; state.pickerSelection = async () => []; state.fixedUuids = [];
      state.httpRequests = []; state.httpResponses = [];
      state.failInsert = undefined; state.snapshot = undefined; db.version = 0;
      cache.clear();
      global.AppStorage = {
        get: (key) => state.appStorage.get(key),
        setOrCreate: (key, value) => state.appStorage.set(key, value)
      };
      global.canIUse = () => true;
      return sandbox;
    }
  };

  // The storage service caches singletons across resets; expose the very object the modules see.
  sandbox.storage = () => loadFile('core/LexiStorageService').LexiStorageService;
  sandbox.prepareStorage = () => {
    const S = sandbox.storage();
    S.store = db; S.appContext = sandbox.contexts; S.notesIndexReady = true;
    S.settings = sandbox.settings; S.initPromise = Promise.resolve();
    S.actionTransaction = false; S.writeQueue = Promise.resolve();
    S.mutationQueue = Promise.resolve(); S.templateQueue = Promise.resolve();
    S.storagePromptNoteId = '';
    return S;
  };
  return sandbox;
}

module.exports = { createSandbox, ETS_ROOT };

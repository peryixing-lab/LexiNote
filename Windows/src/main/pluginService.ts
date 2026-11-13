import { createHash } from 'node:crypto';
import {
  cpSync,
  existsSync,
  lstatSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  renameSync,
  rmSync,
  statSync,
  writeFileSync
} from 'node:fs';
import { join, resolve, sep } from 'node:path';
import {
  PLUGIN_RUNTIME_VERSION,
  type PluginBootAssets,
  type PluginCatalogSnapshot,
  PluginErrorCode,
  type PluginInstallResult,
  PluginLimits,
  type PluginRecord,
  isKnownCapability,
  messageOfPluginError,
  codeOfPluginError,
  raisePluginError
} from '../shared/pluginTypes';
import { PluginAiService } from './pluginAiService';
import {
  PLUGIN_ID_PATTERN,
  desktopOnlyNotice,
  detectPluginKind,
  parsePluginManifest,
  pluginMainProblem,
  validatePluginManifest
} from './pluginManifest';
import { extractPluginZip, scanPluginZip } from './pluginZip';

interface RegistryDiskData {
  version: 1;
  records: PluginRecord[];
  enabledByVault: Record<string, string[]>;
}

const KV_KEY_PATTERN = /^[A-Za-z0-9_.-]{1,64}$/;

function safeFolderSegment(raw: string, fallback: string): string {
  const cleaned = raw.trim().replace(/[^A-Za-z0-9._-]/g, '_');
  return cleaned.length > 0 ? cleaned.slice(0, 80) : fallback;
}

function sha256Hex(buf: Buffer): string {
  return createHash('sha256').update(buf).digest('hex');
}

function stripLegacyHarnessProviders(values: Record<string, string>, pluginId: string): Record<string, string> {
  if (pluginId !== 'lexinote.harness') { return values; }
  const next: Record<string, string> = {};
  for (const [k, v] of Object.entries(values)) {
    if (k !== 'harness.providers.v1') { next[k] = v; }
  }
  return next;
}

export class PluginService {
  readonly userDataDir: string;
  readonly pluginsDir: string;
  readonly stagingDir: string;
  readonly dataDir: string;
  private readonly registryPath: string;
  private readonly permissionsPath: string;
  readonly ai: PluginAiService;

  constructor(userDataDir: string) {
    this.userDataDir = resolve(userDataDir);
    this.pluginsDir = join(this.userDataDir, 'plugins');
    this.stagingDir = join(this.userDataDir, 'plugin-staging');
    this.dataDir = join(this.userDataDir, 'plugin-data');
    this.registryPath = join(this.userDataDir, 'plugin-registry.json');
    this.permissionsPath = join(this.userDataDir, 'plugin-permissions.json');
    this.ai = new PluginAiService(this.userDataDir);
  }

  private atomicWriteJson(filePath: string, value: unknown): void {
    mkdirSync(dirnameSafe(filePath), { recursive: true });
    const tmp = `${filePath}.${process.pid}.${Date.now()}.tmp`;
    writeFileSync(tmp, JSON.stringify(value, null, 2), 'utf8');
    renameSync(tmp, filePath);
  }

  private readRegistry(): RegistryDiskData {
    if (existsSync(this.registryPath)) {
      try {
        const raw = JSON.parse(readFileSync(this.registryPath, 'utf8')) as Partial<RegistryDiskData>;
        const records = Array.isArray(raw.records)
          ? raw.records.filter((r): r is PluginRecord => Boolean(r && typeof r.id === 'string' && r.id.length > 0))
          : [];
        const enabledByVault: Record<string, string[]> = {};
        if (raw.enabledByVault && typeof raw.enabledByVault === 'object') {
          for (const [vaultId, list] of Object.entries(raw.enabledByVault)) {
            if (Array.isArray(list)) {
              enabledByVault[vaultId] = list.filter((id): id is string => typeof id === 'string' && id.length > 0);
            }
          }
        }
        return { version: 1, records, enabledByVault };
      } catch {
        // Corrupted registry resets cleanly instead of crashing startup.
      }
    }
    return { version: 1, records: [], enabledByVault: {} };
  }

  private writeRegistry(data: RegistryDiskData): void {
    this.atomicWriteJson(this.registryPath, data);
  }

  private readPermissionsMap(): Record<string, string[]> {
    if (existsSync(this.permissionsPath)) {
      try {
        const parsed = JSON.parse(readFileSync(this.permissionsPath, 'utf8')) as Record<string, unknown>;
        if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
          const out: Record<string, string[]> = {};
          for (const [pluginId, list] of Object.entries(parsed)) {
            if (Array.isArray(list)) {
              out[pluginId] = list.filter((cap): cap is string => typeof cap === 'string' && isKnownCapability(cap));
            }
          }
          return out;
        }
      } catch {
        // Ignore corrupt permissions file -> default deny
      }
    }
    return {};
  }

  private writePermissionsMap(map: Record<string, string[]>): void {
    this.atomicWriteJson(this.permissionsPath, map);
  }

  private pluginDirOf(pluginId: string): string {
    if (!PLUGIN_ID_PATTERN.test(pluginId)) {
      raisePluginError(PluginErrorCode.INVALID_ARGUMENT, '插件标识非法');
    }
    return join(this.pluginsDir, pluginId);
  }

  snapshot(): PluginCatalogSnapshot {
    const reg = this.readRegistry();
    const perms = this.readPermissionsMap();
    const validIds = new Set<string>();
    const records: PluginRecord[] = reg.records.map((rec) => {
      validIds.add(rec.id);
      const requested = Array.isArray(rec.requestedCapabilities) ? rec.requestedCapabilities : [];
      const rawGranted = perms[rec.id] ?? rec.grantedCapabilities ?? [];
      const granted = rawGranted.filter((cap) => requested.includes(cap) && isKnownCapability(cap));
      return {
        ...rec,
        requestedCapabilities: [...requested],
        grantedCapabilities: granted
      };
    });
    const enabledByVault: Record<string, string[]> = {};
    for (const [vaultId, ids] of Object.entries(reg.enabledByVault)) {
      enabledByVault[vaultId] = ids.filter((id) => validIds.has(id));
    }
    return {
      records,
      enabledByVault,
      pluginsDir: this.pluginsDir
    };
  }

  private finalizeInstallFromStagedDir(
    stagedDir: string,
    sha256: string,
    source: string
  ): PluginInstallResult {
    const manifestPath = join(stagedDir, 'manifest.json');
    if (!existsSync(manifestPath)) {
      return {
        ok: false,
        pluginId: '',
        record: null,
        error: `${PluginErrorCode.INSTALL_REJECTED}: 缺少 manifest.json`,
        warnings: []
      };
    }

    const rawManifest = readFileSync(manifestPath, 'utf8');
    if (!rawManifest.trim()) {
      return {
        ok: false,
        pluginId: '',
        record: null,
        error: `${PluginErrorCode.INSTALL_REJECTED}: manifest.json 为空`,
        warnings: []
      };
    }

    const kind = detectPluginKind(rawManifest);
    let manifest;
    try {
      manifest = parsePluginManifest(rawManifest, kind);
    } catch {
      return {
        ok: false,
        pluginId: '',
        record: null,
        error: `${PluginErrorCode.INSTALL_REJECTED}: manifest.json 不是合法 JSON`,
        warnings: []
      };
    }

    const problems = validatePluginManifest(manifest, kind);
    if (problems.length > 0) {
      return {
        ok: false,
        pluginId: manifest.id,
        record: null,
        error: `${PluginErrorCode.INSTALL_REJECTED}: ${problems[0]}`,
        warnings: []
      };
    }

    const mainAbs = resolve(stagedDir, manifest.main);
    const stagedRoot = resolve(stagedDir);
    if (!mainAbs.startsWith(stagedRoot + sep) || !existsSync(mainAbs)) {
      const files = readdirSync(stagedRoot).slice(0, 8).join(', ');
      return {
        ok: false,
        pluginId: manifest.id,
        record: null,
        error: `${PluginErrorCode.INSTALL_REJECTED}: 入口文件 ${manifest.main} 不存在（目录内：${files}）`,
        warnings: []
      };
    }

    const targetDir = this.pluginDirOf(manifest.id);
    mkdirSync(this.pluginsDir, { recursive: true });
    rmSync(targetDir, { recursive: true, force: true });
    try {
      renameSync(stagedRoot, targetDir);
    } catch {
      cpSync(stagedRoot, targetDir, { recursive: true });
    }

    const reg = this.readRegistry();
    const perms = this.readPermissionsMap();
    const previous = reg.records.find((r) => r.id === manifest.id);
    const prevGranted = perms[manifest.id] ?? previous?.grantedCapabilities ?? [];
    const preservedGranted = prevGranted.filter((cap) => manifest.capabilities.includes(cap));
    perms[manifest.id] = preservedGranted;
    this.writePermissionsMap(perms);

    const record: PluginRecord = {
      id: manifest.id,
      name: manifest.name || manifest.id,
      kind,
      version: manifest.version,
      apiVersion: manifest.apiVersion,
      runtimeVersion: PLUGIN_RUNTIME_VERSION,
      main: manifest.main,
      description: manifest.description,
      author: manifest.author,
      requestedCapabilities: [...manifest.capabilities],
      grantedCapabilities: preservedGranted,
      vaultScopes: previous ? [...previous.vaultScopes] : [],
      installedAt: previous ? previous.installedAt : Date.now(),
      updatedAt: Date.now(),
      sha256,
      source,
      isDesktopOnly: manifest.isDesktopOnly,
      directory: targetDir
    };

    const nextRecords = reg.records.filter((r) => r.id !== manifest.id);
    nextRecords.push(record);
    this.writeRegistry({ ...reg, records: nextRecords });

    const warnings: string[] = [];
    if (record.grantedCapabilities.length === 0 && record.requestedCapabilities.length > 0) {
      warnings.push('插件已安装但未授予任何能力，请在插件设置中逐项授权');
    }
    const desktopMsg = desktopOnlyNotice(manifest);
    if (desktopMsg) { warnings.push(desktopMsg); }

    return {
      ok: true,
      pluginId: record.id,
      record,
      error: '',
      warnings
    };
  }

  installFromZip(zipPath: string): PluginInstallResult {
    const token = `${Date.now()}-${Math.floor(Math.random() * 1e6)}`;
    const stagingRunDir = join(this.stagingDir, token);
    const extractedDir = join(stagingRunDir, 'extracted');
    try {
      if (!zipPath || !existsSync(zipPath)) {
        return {
          ok: false,
          pluginId: '',
          record: null,
          error: `${PluginErrorCode.INSTALL_REJECTED}: 无法读取所选 ZIP 文件`,
          warnings: []
        };
      }
      const stat = statSync(zipPath);
      if (stat.size <= 0) {
        return {
          ok: false,
          pluginId: '',
          record: null,
          error: `${PluginErrorCode.INSTALL_REJECTED}: ZIP 文件为空`,
          warnings: []
        };
      }
      if (stat.size > PluginLimits.MAX_ZIP_BYTES) {
        return {
          ok: false,
          pluginId: '',
          record: null,
          error: `${PluginErrorCode.INSTALL_REJECTED}: 插件包超过大小上限`,
          warnings: []
        };
      }
      const bytes = readFileSync(zipPath);
      const scan = scanPluginZip(bytes);
      if (!scan.ok) {
        return {
          ok: false,
          pluginId: '',
          record: null,
          error: `${PluginErrorCode.INSTALL_REJECTED}: ${scan.problems.slice(0, 3).join('；')}`,
          warnings: []
        };
      }
      extractPluginZip(bytes, scan, extractedDir);
      return this.finalizeInstallFromStagedDir(extractedDir, sha256Hex(bytes), 'zip');
    } catch (error) {
      const code = codeOfPluginError(error);
      return {
        ok: false,
        pluginId: '',
        record: null,
        error: code === PluginErrorCode.UNKNOWN
          ? `${PluginErrorCode.INSTALL_REJECTED}: ${messageOfPluginError(error)}`
          : `${code}: ${messageOfPluginError(error)}`,
        warnings: []
      };
    } finally {
      rmSync(stagingRunDir, { recursive: true, force: true });
    }
  }

  installFromDirectory(sourceDir: string): PluginInstallResult {
    const token = `${Date.now()}-${Math.floor(Math.random() * 1e6)}`;
    const stagingRunDir = join(this.stagingDir, token);
    const copiedDir = join(stagingRunDir, 'folder');
    try {
      const srcRoot = resolve(sourceDir);
      if (!sourceDir || !existsSync(srcRoot) || !statSync(srcRoot).isDirectory()) {
        return {
          ok: false,
          pluginId: '',
          record: null,
          error: `${PluginErrorCode.INSTALL_REJECTED}: 所选插件目录不存在`,
          warnings: []
        };
      }

      let totalBytes = 0;
      let entryCount = 0;
      const hash = createHash('sha256');
      const copyTree = (dir: string, out: string): void => {
        mkdirSync(out, { recursive: true });
        for (const name of readdirSync(dir)) {
          if (name === '__MACOSX' || name === '.DS_Store' || name === 'Thumbs.db' || name === 'desktop.ini' || name.startsWith('._')) {
            continue;
          }
          const srcItem = join(dir, name);
          const lst = lstatSync(srcItem);
          if (lst.isSymbolicLink()) {
            raisePluginError(PluginErrorCode.INSTALL_REJECTED, `不允许包含符号链接：${name}`);
          }
          entryCount += 1;
          if (entryCount > PluginLimits.MAX_ZIP_ENTRIES) {
            raisePluginError(PluginErrorCode.INSTALL_REJECTED, `文件数量超过上限（${PluginLimits.MAX_ZIP_ENTRIES}）`);
          }
          const dstItem = join(out, name);
          if (lst.isDirectory()) {
            copyTree(srcItem, dstItem);
          } else if (lst.isFile()) {
            totalBytes += lst.size;
            if (totalBytes > PluginLimits.MAX_ZIP_BYTES) {
              raisePluginError(PluginErrorCode.INSTALL_REJECTED, `插件总大小超过上限（${PluginLimits.MAX_ZIP_BYTES} 字节）`);
            }
            const data = readFileSync(srcItem);
            hash.update(name);
            hash.update(data);
            writeFileSync(dstItem, data);
          }
        }
      };

      copyTree(srcRoot, copiedDir);
      return this.finalizeInstallFromStagedDir(copiedDir, hash.digest('hex'), 'folder');
    } catch (error) {
      const code = codeOfPluginError(error);
      return {
        ok: false,
        pluginId: '',
        record: null,
        error: code === PluginErrorCode.UNKNOWN
          ? `${PluginErrorCode.INSTALL_REJECTED}: ${messageOfPluginError(error)}`
          : `${code}: ${messageOfPluginError(error)}`,
        warnings: []
      };
    } finally {
      rmSync(stagingRunDir, { recursive: true, force: true });
    }
  }

  uninstallPlugin(pluginId: string, keepData = false): PluginCatalogSnapshot {
    const reg = this.readRegistry();
    const record = reg.records.find((r) => r.id === pluginId);
    const targetDir = record?.directory ? resolve(record.directory) : this.pluginDirOf(pluginId);
    const expectedPrefix = resolve(this.pluginsDir) + sep;
    if (targetDir.startsWith(expectedPrefix)) {
      rmSync(targetDir, { recursive: true, force: true });
    }

    const nextRecords = reg.records.filter((r) => r.id !== pluginId);
    const nextEnabled: Record<string, string[]> = {};
    for (const [vaultId, list] of Object.entries(reg.enabledByVault)) {
      nextEnabled[vaultId] = list.filter((id) => id !== pluginId);
    }
    this.writeRegistry({ version: 1, records: nextRecords, enabledByVault: nextEnabled });

    const perms = this.readPermissionsMap();
    delete perms[pluginId];
    this.writePermissionsMap(perms);

    this.ai.clearFor(pluginId);

    if (!keepData && existsSync(this.dataDir)) {
      const pluginFileName = `${safeFolderSegment(pluginId, 'plugin')}.json`;
      for (const vaultFolder of readdirSync(this.dataDir)) {
        const candidate = join(this.dataDir, vaultFolder, pluginFileName);
        rmSync(candidate, { force: true });
      }
    }

    return this.snapshot();
  }

  readBootAssets(pluginId: string, vaultId: string): PluginBootAssets {
    const reg = this.readRegistry();
    const record = reg.records.find((r) => r.id === pluginId);
    if (!record) {
      raisePluginError(PluginErrorCode.NOT_FOUND, `插件未安装：${pluginId}`);
    }
    const dir = record.directory && existsSync(record.directory) ? resolve(record.directory) : this.pluginDirOf(pluginId);
    const mainRel = record.main || 'main.js';
    const mainIssue = pluginMainProblem(mainRel);
    if (mainIssue) {
      raisePluginError(PluginErrorCode.PLUGIN_FAILED, '插件入口路径非法');
    }
    const mainPath = resolve(dir, mainRel);
    if (!mainPath.startsWith(dir + sep) || !existsSync(mainPath)) {
      raisePluginError(PluginErrorCode.PLUGIN_FAILED, '插件入口文件缺失，请重新安装');
    }

    const manifestPath = join(dir, 'manifest.json');
    const stylesPath = join(dir, 'styles.css');
    const manifestJson = existsSync(manifestPath) ? readFileSync(manifestPath, 'utf8') : '{}';
    const sourceCode = readFileSync(mainPath, 'utf8');
    const stylesCss = existsSync(stylesPath) ? readFileSync(stylesPath, 'utf8') : '';

    const rawKv = this.readKvMap(pluginId, vaultId);
    const cleanedKv = stripLegacyHarnessProviders(rawKv, pluginId);
    const settingsVal = rawKv['plugin-data'];

    return {
      manifestJson,
      sourceCode,
      stylesCss,
      sourceName: mainRel,
      dataJson: JSON.stringify(cleanedKv),
      settingsJson: settingsVal && settingsVal.length > 0 ? settingsVal : 'null',
      platform: process.platform
    };
  }

  setPluginEnabled(vaultId: string, pluginId: string, enabled: boolean): string[] {
    const key = vaultId || 'default';
    const reg = this.readRegistry();
    const exists = reg.records.some((r) => r.id === pluginId);
    if (!exists && enabled) {
      raisePluginError(PluginErrorCode.NOT_FOUND, `插件未安装：${pluginId}`);
    }
    const current = new Set(reg.enabledByVault[key] ?? []);
    if (enabled) {
      current.add(pluginId);
    } else {
      current.delete(pluginId);
    }
    reg.enabledByVault[key] = Array.from(current);
    this.writeRegistry(reg);
    return reg.enabledByVault[key];
  }

  grantCapability(pluginId: string, capability: string): string[] {
    if (!isKnownCapability(capability)) {
      raisePluginError(PluginErrorCode.INVALID_ARGUMENT, `未知能力 ${capability}`);
    }
    const reg = this.readRegistry();
    const record = reg.records.find((r) => r.id === pluginId);
    if (!record) {
      raisePluginError(PluginErrorCode.NOT_FOUND, `插件未安装：${pluginId}`);
    }
    if (!record.requestedCapabilities.includes(capability)) {
      raisePluginError(PluginErrorCode.PERMISSION_DENIED, '插件清单未声明该能力');
    }
    const perms = this.readPermissionsMap();
    const next = new Set(perms[pluginId] ?? []);
    next.add(capability);
    perms[pluginId] = Array.from(next);
    this.writePermissionsMap(perms);
    return perms[pluginId];
  }

  revokeCapability(pluginId: string, capability: string): string[] {
    const perms = this.readPermissionsMap();
    const next = (perms[pluginId] ?? []).filter((cap) => cap !== capability);
    perms[pluginId] = next;
    this.writePermissionsMap(perms);
    return next;
  }

  grantAllCapabilities(pluginId: string): string[] {
    const reg = this.readRegistry();
    const record = reg.records.find((r) => r.id === pluginId);
    if (!record) {
      raisePluginError(PluginErrorCode.NOT_FOUND, `插件未安装：${pluginId}`);
    }
    const perms = this.readPermissionsMap();
    const valid = record.requestedCapabilities.filter((cap) => isKnownCapability(cap));
    perms[pluginId] = Array.from(new Set(valid));
    this.writePermissionsMap(perms);
    return perms[pluginId];
  }

  revokeAllCapabilities(pluginId: string): string[] {
    const perms = this.readPermissionsMap();
    perms[pluginId] = [];
    this.writePermissionsMap(perms);
    return [];
  }

  private kvPath(pluginId: string, vaultId: string): string {
    const vaultFolder = safeFolderSegment(vaultId || 'default', 'default');
    const pluginFile = `${safeFolderSegment(pluginId, 'plugin')}.json`;
    return join(this.dataDir, vaultFolder, pluginFile);
  }

  private readKvMap(pluginId: string, vaultId: string): Record<string, string> {
    const filePath = this.kvPath(pluginId, vaultId);
    if (!existsSync(filePath)) { return {}; }
    try {
      const parsed = JSON.parse(readFileSync(filePath, 'utf8')) as Record<string, unknown>;
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
        const out: Record<string, string> = {};
        for (const [k, v] of Object.entries(parsed)) {
          if (typeof v === 'string') { out[k] = v; }
        }
        return out;
      }
    } catch {
      // Corrupt KV file degrades to empty
    }
    return {};
  }

  private writeKvMap(pluginId: string, vaultId: string, map: Record<string, string>): void {
    this.atomicWriteJson(this.kvPath(pluginId, vaultId), map);
  }

  private assertKvKey(key: string): void {
    if (!KV_KEY_PATTERN.test(key)) {
      raisePluginError(PluginErrorCode.INVALID_ARGUMENT, 'storage key 须为 1-64 位字母/数字/._-');
    }
  }

  kvGet(pluginId: string, vaultId: string, key: string): string {
    this.assertKvKey(key);
    const map = this.readKvMap(pluginId, vaultId);
    return map[key] ?? '';
  }

  kvSet(pluginId: string, vaultId: string, key: string, value: string): void {
    this.assertKvKey(key);
    if (typeof value !== 'string') {
      raisePluginError(PluginErrorCode.INVALID_ARGUMENT, '值必须是字符串');
    }
    const map = this.readKvMap(pluginId, vaultId);
    if (!(key in map) && Object.keys(map).length >= PluginLimits.MAX_STORAGE_KEYS) {
      raisePluginError(PluginErrorCode.QUOTA_EXCEEDED, '插件存储键数量超过上限');
    }
    const next = { ...map, [key]: value };
    let total = 0;
    for (const [k, v] of Object.entries(next)) {
      total += Buffer.byteLength(k, 'utf8') + Buffer.byteLength(v, 'utf8');
    }
    if (total > PluginLimits.MAX_STORAGE_BYTES) {
      raisePluginError(PluginErrorCode.QUOTA_EXCEEDED, '插件存储空间超过上限');
    }
    this.writeKvMap(pluginId, vaultId, next);
  }

  kvRemove(pluginId: string, vaultId: string, key: string): void {
    this.assertKvKey(key);
    const map = this.readKvMap(pluginId, vaultId);
    if (!(key in map)) { return; }
    const next = { ...map };
    delete next[key];
    this.writeKvMap(pluginId, vaultId, next);
  }
}

function dirnameSafe(path: string): string {
  return resolve(path, '..');
}

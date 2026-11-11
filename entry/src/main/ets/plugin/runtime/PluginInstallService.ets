import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { zlib } from '@kit.BasicServicesKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PluginInstallResult, PluginKind, PluginLimits, PluginManifest, PluginRecord, PluginState } from '../model/PluginModels';
import { PluginErrorCode, PluginErrors } from '../model/PluginErrors';
import { PluginRegistry } from '../core/PluginRegistry';
import { PluginManifestService, PluginText } from './PluginManifestService';
import { PluginZip, PluginZipEntry, PluginZipScan } from './PluginZip';

/**
 * Local-only plugin installer (P14).
 *
 * The archive is parsed and validated *before* anything is extracted, extracted into a
 * staging directory, re-verified against the scanned entry list, and only then moved to
 * `<filesDir>/plugins/<pluginId>`. Plugin files never touch the user's knowledge base.
 */
export class PluginInstallService {
  static pluginsRoot(context: common.Context): string {
    return `${context.filesDir}/plugins`;
  }

  static stagingRoot(context: common.Context): string {
    return `${context.filesDir}/plugin-staging`;
  }

  static pluginDirectory(context: common.Context, pluginId: string): string {
    if (!PluginManifestService.ID_PATTERN.test(pluginId)) {
      throw PluginErrors.raise(PluginErrorCode.INVALID_ARGUMENT, '插件标识非法');
    }
    return `${PluginInstallService.pluginsRoot(context)}/${pluginId}`;
  }

  private static token(): string {
    return `${Date.now()}-${Math.floor(Math.random() * 1000000)}`;
  }

  static detectKind(raw: string): string {
    try {
      const parsed = JSON.parse(raw) as PluginManifest;
      return parsed.format === 'lexinote-plugin' ? PluginKind.LEXINOTE : PluginKind.OBSIDIAN;
    } catch (error) {
      return PluginKind.OBSIDIAN;
    }
  }

  private static readFileBytes(path: string): Uint8Array {
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const stat = fs.statSync(path);
      const size = stat.size;
      if (size <= 0) { throw PluginErrors.raise(PluginErrorCode.INSTALL_REJECTED, 'manifest.json 为空'); }
      const buffer = new ArrayBuffer(size);
      fs.readSync(file.fd, buffer);
      return new Uint8Array(buffer);
    } finally {
      fs.closeSync(file);
    }
  }

  static readFileText(path: string): string {
    return PluginText.decodeUtf8(PluginInstallService.readFileBytes(path).slice(0));
  }

  private static writeBytes(path: string, bytes: Uint8Array): void {
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
    } finally {
      fs.closeSync(file);
    }
  }

  static sha256(bytes: Uint8Array): string {
    try {
      const digest = cryptoFramework.createMd('SHA256');
      digest.updateSync({ data: bytes });
      const result = digest.digestSync();
      let hex = '';
      for (const byte of result.data) { hex += byte.toString(16).padStart(2, '0'); }
      return hex;
    } catch (error) {
      return '';
    }
  }

  /** `mkdirSync(path, true)` throws when the directory already exists; this does not. */
  private static ensureDirectory(path: string): void {
    try {
      if (!fs.accessSync(path)) { fs.mkdirSync(path, true); }
    } catch (error) {
      if (!fs.accessSync(path)) { throw error as Error; }
    }
  }

  private static removeDirectory(path: string): void {
    try {
      if (fs.accessSync(path)) { fs.rmdirSync(path); }
    } catch (error) {
      // Best effort: a leftover staging directory must never block installation.
    }
  }

  private static listNames(directory: string): string[] {
    try {
      return fs.listFileSync(directory);
    } catch (error) {
      return [];
    }
  }

  private static walk(directory: string, prefix: string, collected: string[]): void {
    for (const name of PluginInstallService.listNames(directory)) {
      const path = `${directory}/${name}`;
      let isDirectory = false;
      try {
        isDirectory = fs.statSync(path).isDirectory();
      } catch (error) {
        isDirectory = false;
      }
      const relative = prefix.length > 0 ? `${prefix}/${name}` : name;
      if (isDirectory) {
        collected.push(`${relative}/`);
        PluginInstallService.walk(path, relative, collected);
      } else {
        collected.push(relative);
      }
    }
  }

  /** Verifies the extracted tree matches exactly what the scanner approved. */
  private static verifyExtraction(scan: PluginZipScan, extractDir: string): string[] {
    const root = scan.commonRoot.length > 0 ? `${extractDir}/${scan.commonRoot}` : extractDir;
    if (!fs.accessSync(root)) { return ['解压目录不存在']; }
    const expected: string[] = [];
    for (const entry of scan.entries) {
      const name = entry.name.replace(/\/+$/, '');
      // 归档元数据与插件目录之外的散落文件都会在安装后丢弃，不参与"解压结果=扫描结果"对账。
      if (PluginZip.isArchiveMetadata(name)) { continue; }
      if (scan.commonRoot.length > 0 && !name.startsWith(`${scan.commonRoot}/`)) { continue; }
      expected.push(entry.isDirectory ? `${PluginZip.relativeName(scan, entry)}/` : PluginZip.relativeName(scan, entry));
    }
    const actual: string[] = [];
    PluginInstallService.walk(root, '', actual);
    const relevant = actual.filter((item: string): boolean => !PluginZip.isArchiveMetadata(item));
    const problems: string[] = [];
    for (const item of relevant) {
      if (!expected.includes(item)) { problems.push(`解压后出现未声明的文件：${item}`); }
    }
    for (const item of expected) {
      if (!relevant.includes(item)) { problems.push(`解压后缺少文件：${item}`); }
    }
    return problems;
  }

  private static async extract(zipPath: string, extractDir: string): Promise<void> {
    try {
      // zlib rejects a destination that does not exist yet (BusinessError 900002).
      PluginInstallService.ensureDirectory(extractDir);
      await zlib.decompressFile(zipPath, extractDir);
    } catch (error) {
      throw PluginErrors.raise(PluginErrorCode.INSTALL_REJECTED,
        `ZIP 解压失败：${PluginErrors.messageOf(error as BusinessError)}`);
    }
  }

  /** Best-effort removal of archive metadata that extraction copied into the plugin folder. */
  private static dropArchiveMetadata(target: string): void {
    PluginInstallService.removeDirectory(`${target}/__MACOSX`);
    for (const name of PluginInstallService.listNames(target)) {
      if (!PluginZip.isArchiveMetadata(name)) { continue; }
      const path = `${target}/${name}`;
      try {
        const isDirectory = fs.statSync(path).isDirectory();
        if (isDirectory) { PluginInstallService.removeDirectory(path); }
        else { fs.unlinkSync(path); }
      } catch (error) {
        // Cleanup is cosmetic: never fail an installed plugin because junk could not be removed.
      }
    }
  }

  private static existingRecord(pluginId: string): PluginRecord | undefined {
    return PluginRegistry.get(pluginId);
  }

  private static buildRecord(manifest: PluginManifest, kind: string, directory: string, sha256: string,
    source: string): PluginRecord {
    const previous = PluginInstallService.existingRecord(manifest.id);
    const record = new PluginRecord();
    record.id = manifest.id;
    record.name = manifest.name || manifest.id;
    record.kind = kind;
    record.version = manifest.version;
    record.apiVersion = manifest.apiVersion;
    record.main = manifest.main;
    record.description = manifest.description;
    record.author = manifest.author;
    record.requestedCapabilities = manifest.capabilities.slice(0);
    record.grantedCapabilities = previous
      ? previous.grantedCapabilities.filter((capability: string): boolean =>
        manifest.capabilities.includes(capability))
      : [];
    record.vaultScopes = previous ? previous.vaultScopes.slice(0) : [];
    record.enabled = false;
    record.state = PluginState.INSTALLED_DISABLED;
    record.installedAt = previous ? previous.installedAt : Date.now();
    record.updatedAt = Date.now();
    record.sha256 = sha256;
    record.source = source;
    record.isDesktopOnly = manifest.isDesktopOnly;
    record.lastError = '';
    record.directory = directory;
    return record;
  }

  /**
   * Installs from a user-selected archive. `sourceUri` comes from the system file picker.
   * Everything is validated before a single byte is written into the plugin directory.
   */
  static async installZip(context: common.Context, sourceUri: string): Promise<PluginInstallResult> {
    const result = new PluginInstallResult();
    const staging = `${PluginInstallService.stagingRoot(context)}/${PluginInstallService.token()}`;
    try {
      PluginInstallService.ensureDirectory(staging);
      const zipPath = `${staging}/package.zip`;
      const buffer = new ArrayBuffer(PluginLimits.MAX_ZIP_BYTES + 1);
      const file = fs.openSync(sourceUri, fs.OpenMode.READ_ONLY);
      let bytesRead = 0;
      try {
        bytesRead = fs.readSync(file.fd, buffer);
      } finally {
        fs.closeSync(file);
      }
      if (bytesRead <= 0) {
        result.error = `${PluginErrorCode.INSTALL_REJECTED}: 无法读取所选文件`;
        return result;
      }
      if (bytesRead > PluginLimits.MAX_ZIP_BYTES) {
        result.error = `${PluginErrorCode.INSTALL_REJECTED}: 插件包超过大小上限`;
        return result;
      }
      const bytes = new Uint8Array(buffer, 0, bytesRead);
      PluginInstallService.writeBytes(zipPath, bytes);

      const scan = PluginZip.scan(bytes);
      if (!scan.ok) {
        result.error = `${PluginErrorCode.INSTALL_REJECTED}: ${scan.problems.slice(0, 3).join('；')}`;
        return result;
      }

      const extractDir = `${staging}/extracted`;
      await PluginInstallService.extract(zipPath, extractDir);
      const problems = PluginInstallService.verifyExtraction(scan, extractDir);
      if (problems.length > 0) {
        result.error = `${PluginErrorCode.INSTALL_REJECTED}: ${problems[0]}`;
        return result;
      }

      const root = scan.commonRoot.length > 0 ? `${extractDir}/${scan.commonRoot}` : extractDir;
      const manifestPath = `${root}/manifest.json`;
      if (!fs.accessSync(manifestPath)) {
        result.error = `${PluginErrorCode.INSTALL_REJECTED}: 缺少 manifest.json`;
        return result;
      }
      const rawManifest = PluginInstallService.readFileText(manifestPath);
      const kind = PluginInstallService.detectKind(rawManifest);
      let manifest: PluginManifest;
      try {
        manifest = PluginManifestService.parse(rawManifest, kind);
      } catch (error) {
        result.error = `${PluginErrorCode.INSTALL_REJECTED}: manifest.json 不是合法 JSON`;
        return result;
      }
      const manifestProblems = PluginManifestService.validate(manifest, kind);
      if (manifestProblems.length > 0) {
        result.error = `${PluginErrorCode.INSTALL_REJECTED}: ${manifestProblems[0]}`;
        return result;
      }
      if (!fs.accessSync(`${root}/${manifest.main}`)) {
        // 目录里到底有什么，让用户自己判断是"源码包"还是"打包位置不对"。
        result.error = `${PluginErrorCode.INSTALL_REJECTED}: 入口文件 ${manifest.main} 不存在` +
          `（插件目录内：${PluginInstallService.listNames(root).slice(0, 8).join(', ')}）`;
        return result;
      }
      const target = PluginInstallService.pluginDirectory(context, manifest.id);
      PluginInstallService.ensureDirectory(PluginInstallService.pluginsRoot(context));
      PluginInstallService.removeDirectory(target);
      fs.renameSync(root, target);
      // 归档元数据（__MACOSX/、._*、.DS_Store）会被解压工具一并写出；它们对插件无用，
      // 移入插件目录后清掉，避免插件目录里出现读者解释不了的文件。
      PluginInstallService.dropArchiveMetadata(target);

      const record = PluginInstallService.buildRecord(manifest, kind, target,
        PluginInstallService.sha256(bytes), 'file');
      await PluginRegistry.upsert(record);
      result.ok = true;
      result.pluginId = record.id;
      result.record = record;
      if (record.grantedCapabilities.length === 0 && record.requestedCapabilities.length > 0) {
        result.warnings.push('插件已安装但未授予任何能力，请在插件设置中逐项授权');
      }
      const desktopNotice = PluginManifestService.desktopOnlyNotice(manifest);
      if (desktopNotice.length > 0) { result.warnings.push(desktopNotice); }
      return result;
    } catch (error) {
      const code = PluginErrors.codeOf(error);
      result.error = code === PluginErrorCode.UNKNOWN
        ? `${PluginErrorCode.INSTALL_REJECTED}: ${PluginErrors.messageOf(error)}`
        : `${code}: ${PluginErrors.messageOf(error)}`;
      return result;
    } finally {
      PluginInstallService.removeDirectory(staging);
    }
  }

  /** Reads the plugin entry bundle for the runtime. */
  static async readSource(context: common.Context, record: PluginRecord): Promise<string> {
    const directory = record.directory.length > 0 ? record.directory :
      PluginInstallService.pluginDirectory(context, record.id);
    const main = record.main.length > 0 ? record.main : 'main.js';
    if (PluginManifestService.mainProblem(main).length > 0) {
      throw PluginErrors.raise(PluginErrorCode.PLUGIN_FAILED, '插件入口路径非法');
    }
    const path = `${directory}/${main}`;
    if (!fs.accessSync(path)) {
      throw PluginErrors.raise(PluginErrorCode.PLUGIN_FAILED, '插件入口文件缺失，请重新安装');
    }
    const bytes = PluginInstallService.readFileBytes(path);
    return PluginText.decodeUtf8(bytes);
  }

  static async readManifestJson(context: common.Context, record: PluginRecord): Promise<string> {
    const directory = record.directory.length > 0 ? record.directory :
      PluginInstallService.pluginDirectory(context, record.id);
    const path = `${directory}/manifest.json`;
    if (!fs.accessSync(path)) { return '{}'; }
    return PluginInstallService.readFileText(path);
  }

  /** Removes the installed files and the catalogue record. User data is cleared by the manager. */
  static async uninstall(context: common.Context, pluginId: string): Promise<void> {
    const record = PluginRegistry.get(pluginId);
    await PluginRegistry.setState(pluginId, PluginState.UNINSTALLING);
    const directory = record && record.directory.length > 0
      ? record.directory : PluginInstallService.pluginDirectory(context, pluginId);
    PluginInstallService.removeDirectory(directory);
    await PluginRegistry.remove(pluginId);
  }

  /** Lists installed plugin files for the diagnostics panel. */
  static listPluginFiles(context: common.Context, pluginId: string): string[] {
    const directory = PluginInstallService.pluginDirectory(context, pluginId);
    const collected: string[] = [];
    PluginInstallService.walk(directory, '', collected);
    return collected;
  }

  static entriesOf(scan: PluginZipScan): PluginZipEntry[] {
    return scan.entries;
  }
}

import { PluginLimits } from '../model/PluginModels';

export class PluginZipEntry {
  name: string = '';
  compressedSize: number = 0;
  uncompressedSize: number = 0;
  method: number = 0;
  isDirectory: boolean = false;
  isSymlink: boolean = false;
  localHeaderOffset: number = 0;
}

export class PluginZipScan {
  entries: PluginZipEntry[] = [];
  totalUncompressed: number = 0;
  commonRoot: string = '';
  problems: string[] = [];
  ok: boolean = false;
}

/**
 * ZIP central-directory reader used before any extraction happens.
 *
 * Nothing here writes to disk: it decides whether the archive may be unpacked at all.
 * The checks mirror the install checklist in docs/plugin-system/04-security.md —
 * entry count, total uncompressed size, compressed method, absolute paths, `..` segments,
 * backslashes, drive letters, symbolic links and a single shared root folder.
 */
export class PluginZip {
  /**
   * macOS/Windows 归档工具会写入同步元数据（`__MACOSX/` 资源叉、`._*`、`.DS_Store`、
   * `Thumbs.db`）。它们不是插件内容，却会把"单一共享根目录"拆成两个根，让合法插件被判
   * "根目录缺少 manifest.json"——macOS 上右键"压缩"生成的包几乎必然带 `__MACOSX/`。
   * 这些路径仍参与路径安全校验，但不参与根目录推导与 manifest 存在性判断。
   */
  static isArchiveMetadata(name: string): boolean {
    const trimmed = name.replace(/\/+$/, '');
    if (trimmed.length === 0) { return false; }
    const parts = trimmed.split('/');
    const base = parts[parts.length - 1];
    if (parts[0] === '__MACOSX') { return true; }
    if (base === '.DS_Store' || base === 'Thumbs.db' || base === 'desktop.ini') { return true; }
    return base.startsWith('._');
  }

  private static readonly EOCD_SIGNATURE: number = 0x06054b50;
  private static readonly CENTRAL_SIGNATURE: number = 0x02014b50;
  private static readonly MAX_COMMENT: number = 65535;

  static scan(bytes: Uint8Array): PluginZipScan {
    const scan = new PluginZipScan();
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    const length = bytes.byteLength;
    if (length < 22) {
      scan.problems.push('不是有效的 ZIP 文件');
      return scan;
    }
    const eocd = PluginZip.findEocd(view, length);
    if (eocd < 0) {
      scan.problems.push('未找到 ZIP 中央目录');
      return scan;
    }
    const entryCount = view.getUint16(eocd + 10, true);
    const directorySize = view.getUint32(eocd + 12, true);
    const directoryOffset = view.getUint32(eocd + 16, true);
    if (entryCount === 0) { scan.problems.push('插件包为空'); }
    if (entryCount > PluginLimits.MAX_ZIP_ENTRIES) {
      scan.problems.push(`文件数量超过上限（${PluginLimits.MAX_ZIP_ENTRIES}）`);
      return scan;
    }
    if (directoryOffset + directorySize > length) {
      scan.problems.push('中央目录越界');
      return scan;
    }
    if (directorySize > PluginLimits.MAX_ZIP_BYTES) {
      scan.problems.push('目录体积异常');
      return scan;
    }

    let cursor = directoryOffset;
    for (let index = 0; index < entryCount; index++) {
      if (cursor + 46 > length || view.getUint32(cursor, true) !== PluginZip.CENTRAL_SIGNATURE) {
        scan.problems.push('中央目录条目损坏');
        return scan;
      }
      const method = view.getUint16(cursor + 10, true);
      const compressedSize = view.getUint32(cursor + 20, true);
      const uncompressedSize = view.getUint32(cursor + 24, true);
      const nameLength = view.getUint16(cursor + 28, true);
      const extraLength = view.getUint16(cursor + 30, true);
      const commentLength = view.getUint16(cursor + 32, true);
      const externalAttributes = view.getUint32(cursor + 38, true);
      const localHeaderOffset = view.getUint32(cursor + 42, true);
      if (nameLength === 0 || cursor + 46 + nameLength > length) {
        scan.problems.push('条目名越界');
        return scan;
      }
      let name = '';
      for (let offset = 0; offset < nameLength; offset++) {
        name += String.fromCharCode(view.getUint8(cursor + 46 + offset));
      }
      const entry = new PluginZipEntry();
      entry.name = name;
      entry.method = method;
      entry.compressedSize = compressedSize;
      entry.uncompressedSize = uncompressedSize;
      entry.localHeaderOffset = localHeaderOffset;
      entry.isDirectory = name.endsWith('/');
      const mode = externalAttributes >>> 16;
      entry.isSymlink = (mode & 0xF000) === 0xA000;
      scan.entries.push(entry);
      scan.totalUncompressed += uncompressedSize;
      cursor += 46 + nameLength + extraLength + commentLength;
    }

    scan.commonRoot = PluginZip.detectCommonRoot(scan.entries);
    scan.problems = scan.problems.concat(PluginZip.validate(scan));
    scan.ok = scan.problems.length === 0;
    return scan;
  }

  /**
   * The plugin folder inside the archive.
   *
   * Two shapes are accepted:
   *   1. everything shares one first segment (GitHub "Download ZIP");
   *   2. exactly one top-level folder *contains* `manifest.json`, with stray top-level
   *      files tolerated — Finder/`zip` on macOS likes to add sibling junk (AppleDouble
   *      files without the `._` prefix, `.DS_Store`, resource forks). Picking that folder
   *      is unambiguous because there is only one candidate and it is a real plugin.
   * Flat archives (no folder) keep returning ''.
   */
  private static detectCommonRoot(entries: PluginZipEntry[]): string {
    if (entries.length === 0) { return ''; }
    const firstName = entries[0].name.replace(/\/+$/, '');
    const slash = firstName.indexOf('/');
    // 第一个条目可能是根上的散落文件（macOS 归档常见），此时共享根不成立，
    // 但"唯一包含 manifest.json 的顶层目录"仍然可能是插件目录。
    if (slash > 0) {
      const candidate = firstName.substring(0, slash);
      const prefix = `${candidate}/`;
      let shared = true;
      for (const entry of entries) {
        const trimmed = entry.name.replace(/\/+$/, '');
        // 归档元数据不参与根目录推导：`__MACOSX/…` 与插件目录并列时不应把根判成"无共享根"。
        if (PluginZip.isArchiveMetadata(trimmed)) { continue; }
        if (!trimmed.startsWith(prefix)) { shared = false; break; }
      }
      if (shared) { return candidate; }
    }
    return PluginZip.detectSinglePluginFolder(entries);
  }

  /**
   * Unique top-level folder that contains manifest.json.
   *
   * Sibling noise tolerated here is deliberately narrow: archiver artifacts whose name is
   * exactly a top-level folder name and that carry no extension (macOS `zip`/AppleDouble
   * leftovers). A sibling file with a real name/extension still makes the archive ambiguous
   * and is rejected as a structural problem.
   */
  private static detectSinglePluginFolder(entries: PluginZipEntry[]): string {
    const folders: Set<string> = new Set<string>();
    for (const entry of entries) {
      const trimmed = entry.name.replace(/\/+$/, '');
      if (PluginZip.isArchiveMetadata(trimmed)) { continue; }
      const slash = trimmed.indexOf('/');
      if (slash > 0) { folders.add(trimmed.substring(0, slash)); }
    }
    if (folders.size === 0) { return ''; }
    for (const entry of entries) {
      const trimmed = entry.name.replace(/\/+$/, '');
      if (trimmed.length === 0 || trimmed.indexOf('/') > 0) { continue; }
      if (PluginZip.isArchiveMetadata(trimmed)) { continue; }
      // 与候选目录同名的根级条目 = 同一目录的另一种写法（有的工具不带结尾斜杠），
      // 不能用"有没有扩展名"判断：插件目录名常含版本点号（…-1.4.0）。
      const looksLikeFolderArtifact = folders.has(trimmed);
      if (!looksLikeFolderArtifact) { return ''; }
    }
    for (const folder of Array.from(folders)) {
      const manifest = `${folder}/manifest.json`;
      for (const entry of entries) {
        if (entry.name.replace(/\/+$/, '') === manifest) { return folder; }
      }
    }
    return '';
  }

  private static findEocd(view: DataView, length: number): number {
    const limit = Math.max(0, length - PluginZip.MAX_COMMENT - 22);
    for (let offset = length - 22; offset >= limit; offset--) {
      if (view.getUint32(offset, true) === PluginZip.EOCD_SIGNATURE) { return offset; }
    }
    return -1;
  }

  /** Structural and path policy checks. Returns an empty list when the archive is acceptable. */
  static validate(scan: PluginZipScan): string[] {
    const problems: string[] = [];
    if (scan.entries.length === 0) { problems.push('插件包没有文件'); }
    if (scan.totalUncompressed > PluginLimits.MAX_ZIP_BYTES) {
      problems.push(`解压后体积超过上限（${PluginLimits.MAX_ZIP_BYTES} 字节）`);
    }
    const seen: Set<string> = new Set<string>();
    let hasManifest = false;
    for (const entry of scan.entries) {
      const name = entry.name.replace(/\/+$/, '');
      const issue = PluginZip.checkName(name);
      if (issue.length > 0) {
        problems.push(`${entry.name}: ${issue}`);
        continue;
      }
      const key = name.toLowerCase();
      if (seen.has(key)) { problems.push(`重复路径：${entry.name}`); }
      seen.add(key);
      if (entry.isSymlink) { problems.push(`不允许符号链接：${entry.name}`); }
      if (entry.method !== 0 && entry.method !== 8) {
        problems.push(`不支持的压缩方式 ${entry.method}：${entry.name}`);
      }
      if (entry.uncompressedSize > 0 && entry.compressedSize === 0) {
        problems.push(`压缩体积异常：${entry.name}`);
      }
      if (PluginZip.isArchiveMetadata(name)) { continue; }
      const relative = scan.commonRoot.length > 0 ? name.substring(scan.commonRoot.length + 1) : name;
      if (relative === 'manifest.json') { hasManifest = true; }
    }
    if (!hasManifest) {
      problems.push('插件包根目录缺少 manifest.json（包内顶层：' + PluginZip.topLevelSummary(scan) + '）');
    }
    // A shared root must explain *every* entry. A stray root-level file beside the wrapper
    // folder would be unpacked outside the plugin directory, so the archive is refused with a
    // structure error instead of a confusing "missing file" error later.
    if (scan.commonRoot.length > 0) {
      const prefix = `${scan.commonRoot}/`;
      for (const entry of scan.entries) {
        const name = entry.name.replace(/\/+$/, '');
        if (name.length === 0 || PluginZip.isArchiveMetadata(name)) { continue; }
        // 目录项 `wrapper/` 自身必须放行：zip/Finder 会把包装目录作为独立条目写进归档，
        // 它 trimmed 后等于 commonRoot，不以 `wrapper/` 开头。曾经的写法在这里把所有
        // 带目录项的包（macOS「压缩」、`zip -r`、GitHub Download ZIP）整包判成结构异常。
        // 目录项 `wrapper/` 自身必须放行（zip/Finder 会把它作为独立条目写进归档）；
        // 有些工具还把同一目录写成不带斜杠的 `wrapper`，trim 后与 commonRoot 相同，同样放行。
        if (name === scan.commonRoot) { continue; }
        if (!name.startsWith(prefix)) {
          problems.push(`插件包结构异常：${entry.name} 不在插件文件夹 ${scan.commonRoot}/ 内`);
          break;
        }
      }
    }
    return problems;
  }

  /** 顶层条目摘要（最多 6 项），让"根目录缺 manifest"这条错误自己说明包结构。 */
  static topLevelSummary(scan: PluginZipScan): string {
    const names: Set<string> = new Set<string>();
    for (const entry of scan.entries) {
      if (PluginZip.isArchiveMetadata(entry.name)) { continue; }
      const trimmed = entry.name.replace(/\/+$/, '');
      const slash = trimmed.indexOf('/');
      names.add(slash > 0 ? trimmed.substring(0, slash) + '/' : trimmed);
      if (names.size >= 6) { break; }
    }
    if (names.size === 0) { return scan.entries.length === 0 ? '空包' : '仅含归档元数据'; }
    return Array.from(names).join(', ');
  }

  static checkName(name: string): string {
    if (name.length === 0) { return '空文件名'; }
    if (name.length > PluginLimits.MAX_PATH_LENGTH) { return '文件名过长'; }
    if (name.startsWith('/')) { return '不允许绝对路径'; }
    if (name.includes('\\')) { return '不允许反斜杠路径'; }
    if (name.includes(':')) { return '不允许驱动器或 URI'; }
    if (/[\u0000-\u001f\u007f]/.test(name)) { return '文件名含控制字符'; }
    for (const part of name.split('/')) {
      if (part === '.' || part === '..') { return '包含路径穿越'; }
      if (part.length === 0) { return '包含空路径段'; }
    }
    return '';
  }

  /** Maps an archive entry to its path inside the plugin folder. */
  static relativeName(scan: PluginZipScan, entry: PluginZipEntry): string {
    const name = entry.name.replace(/\/+$/, '');
    if (scan.commonRoot.length > 0 && name.startsWith(`${scan.commonRoot}/`)) {
      return name.substring(scan.commonRoot.length + 1);
    }
    return name;
  }
}

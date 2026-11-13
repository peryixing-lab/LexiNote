import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve, sep } from 'node:path';
import { inflateRawSync } from 'node:zlib';
import { PluginErrorCode, PluginLimits, raisePluginError } from '../shared/pluginTypes';

export interface PluginZipEntry {
  name: string;
  flags: number;
  method: number;
  compressedSize: number;
  uncompressedSize: number;
  isDirectory: boolean;
  isSymlink: boolean;
  localHeaderOffset: number;
}

export interface PluginZipScan {
  entries: PluginZipEntry[];
  totalUncompressed: number;
  commonRoot: string;
  problems: string[];
  ok: boolean;
}

const EOCD_SIGNATURE = 0x06054b50;
const CENTRAL_SIGNATURE = 0x02014b50;
const LOCAL_SIGNATURE = 0x04034b50;
const MAX_COMMENT = 65535;

export function isArchiveMetadata(name: string): boolean {
  const trimmed = name.replace(/\/+$/, '');
  if (!trimmed) { return false; }
  const parts = trimmed.split('/');
  const base = parts[parts.length - 1];
  if (parts[0] === '__MACOSX') { return true; }
  if (base === '.DS_Store' || base === 'Thumbs.db' || base === 'desktop.ini') { return true; }
  return base.startsWith('._');
}

function findEocd(buf: Buffer): number {
  const limit = Math.max(0, buf.length - MAX_COMMENT - 22);
  for (let offset = buf.length - 22; offset >= limit; offset -= 1) {
    if (buf.readUInt32LE(offset) === EOCD_SIGNATURE) {
      return offset;
    }
  }
  return -1;
}

export function checkZipEntryName(name: string): string {
  if (!name) { return '空文件名'; }
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

function detectSinglePluginFolder(entries: PluginZipEntry[]): string {
  const folders = new Set<string>();
  for (const entry of entries) {
    const trimmed = entry.name.replace(/\/+$/, '');
    if (isArchiveMetadata(trimmed)) { continue; }
    const slash = trimmed.indexOf('/');
    if (slash > 0) {
      folders.add(trimmed.slice(0, slash));
    }
  }
  if (folders.size === 0) { return ''; }
  for (const entry of entries) {
    const trimmed = entry.name.replace(/\/+$/, '');
    if (!trimmed || trimmed.indexOf('/') > 0) { continue; }
    if (isArchiveMetadata(trimmed)) { continue; }
    if (!folders.has(trimmed)) { return ''; }
  }
  for (const folder of folders) {
    const manifestPath = `${folder}/manifest.json`;
    if (entries.some((entry) => entry.name.replace(/\/+$/, '') === manifestPath)) {
      return folder;
    }
  }
  return '';
}

function detectCommonRoot(entries: PluginZipEntry[]): string {
  if (entries.length === 0) { return ''; }
  const firstName = entries[0].name.replace(/\/+$/, '');
  const slash = firstName.indexOf('/');
  if (slash > 0) {
    const candidate = firstName.slice(0, slash);
    const prefix = `${candidate}/`;
    let shared = true;
    for (const entry of entries) {
      const trimmed = entry.name.replace(/\/+$/, '');
      if (isArchiveMetadata(trimmed)) { continue; }
      if (trimmed === candidate) { continue; }
      if (!trimmed.startsWith(prefix)) {
        shared = false;
        break;
      }
    }
    if (shared) { return candidate; }
  }
  return detectSinglePluginFolder(entries);
}

function topLevelSummary(scan: PluginZipScan): string {
  const names = new Set<string>();
  for (const entry of scan.entries) {
    if (isArchiveMetadata(entry.name)) { continue; }
    const trimmed = entry.name.replace(/\/+$/, '');
    const slash = trimmed.indexOf('/');
    names.add(slash > 0 ? `${trimmed.slice(0, slash)}/` : trimmed);
    if (names.size >= 6) { break; }
  }
  if (names.size === 0) {
    return scan.entries.length === 0 ? '空包' : '仅含归档元数据';
  }
  return Array.from(names).join(', ');
}

export function relativeZipEntryName(scan: PluginZipScan, entry: PluginZipEntry): string {
  const name = entry.name.replace(/\/+$/, '');
  if (scan.commonRoot.length > 0 && name.startsWith(`${scan.commonRoot}/`)) {
    return name.slice(scan.commonRoot.length + 1);
  }
  return name;
}

export function scanPluginZip(buf: Buffer): PluginZipScan {
  const scan: PluginZipScan = {
    entries: [],
    totalUncompressed: 0,
    commonRoot: '',
    problems: [],
    ok: false
  };

  if (buf.length < 22) {
    scan.problems.push('不是有效的 ZIP 文件');
    return scan;
  }
  if (buf.length > PluginLimits.MAX_ZIP_BYTES) {
    scan.problems.push(`插件包超过大小上限（${PluginLimits.MAX_ZIP_BYTES} 字节）`);
    return scan;
  }
  const eocd = findEocd(buf);
  if (eocd < 0) {
    scan.problems.push('未找到 ZIP 中央目录');
    return scan;
  }
  const diskNum = buf.readUInt16LE(eocd + 4);
  const cdDisk = buf.readUInt16LE(eocd + 6);
  const diskEntries = buf.readUInt16LE(eocd + 8);
  const entryCount = buf.readUInt16LE(eocd + 10);
  const directorySize = buf.readUInt32LE(eocd + 12);
  const directoryOffset = buf.readUInt32LE(eocd + 16);

  if (diskNum !== 0 || cdDisk !== 0 || diskEntries !== entryCount) {
    scan.problems.push('不支持分卷 ZIP');
    return scan;
  }
  if (entryCount === 0) {
    scan.problems.push('插件包为空');
    return scan;
  }
  if (entryCount > PluginLimits.MAX_ZIP_ENTRIES) {
    scan.problems.push(`文件数量超过上限（${PluginLimits.MAX_ZIP_ENTRIES}）`);
    return scan;
  }
  if (directoryOffset + directorySize > buf.length) {
    scan.problems.push('中央目录越界');
    return scan;
  }

  let cursor = directoryOffset;
  for (let i = 0; i < entryCount; i += 1) {
    if (cursor + 46 > buf.length || buf.readUInt32LE(cursor) !== CENTRAL_SIGNATURE) {
      scan.problems.push('中央目录条目损坏');
      return scan;
    }
    const flags = buf.readUInt16LE(cursor + 8);
    const method = buf.readUInt16LE(cursor + 10);
    const compressedSize = buf.readUInt32LE(cursor + 20);
    const uncompressedSize = buf.readUInt32LE(cursor + 24);
    const nameLength = buf.readUInt16LE(cursor + 28);
    const extraLength = buf.readUInt16LE(cursor + 30);
    const commentLength = buf.readUInt16LE(cursor + 32);
    const externalAttributes = buf.readUInt32LE(cursor + 38);
    const localHeaderOffset = buf.readUInt32LE(cursor + 42);

    if (nameLength === 0 || cursor + 46 + nameLength > buf.length) {
      scan.problems.push('条目名越界');
      return scan;
    }
    const nameBuf = buf.subarray(cursor + 46, cursor + 46 + nameLength);
    const name = nameBuf.toString((flags & 0x0800) !== 0 ? 'utf8' : 'utf8');
    const mode = externalAttributes >>> 16;
    const entry: PluginZipEntry = {
      name,
      flags,
      method,
      compressedSize,
      uncompressedSize,
      isDirectory: name.endsWith('/'),
      isSymlink: (mode & 0xf000) === 0xa000,
      localHeaderOffset
    };
    scan.entries.push(entry);
    scan.totalUncompressed += uncompressedSize;
    cursor += 46 + nameLength + extraLength + commentLength;
  }

  scan.commonRoot = detectCommonRoot(scan.entries);

  if (scan.totalUncompressed > PluginLimits.MAX_ZIP_BYTES) {
    scan.problems.push(`解压后体积超过上限（${PluginLimits.MAX_ZIP_BYTES} 字节）`);
  }

  const seen = new Set<string>();
  let hasManifest = false;
  for (const entry of scan.entries) {
    const trimmed = entry.name.replace(/\/+$/, '');
    const nameIssue = checkZipEntryName(trimmed);
    if (nameIssue) {
      scan.problems.push(`${entry.name}: ${nameIssue}`);
      continue;
    }
    const key = trimmed.toLowerCase();
    if (seen.has(key)) {
      scan.problems.push(`重复路径：${entry.name}`);
    }
    seen.add(key);
    if ((entry.flags & 0x01) !== 0) {
      scan.problems.push(`不支持加密条目：${entry.name}`);
    }
    if (entry.isSymlink) {
      scan.problems.push(`不允许符号链接：${entry.name}`);
    }
    if (entry.method !== 0 && entry.method !== 8) {
      scan.problems.push(`不支持的压缩方式 ${entry.method}：${entry.name}`);
    }
    if (!entry.isDirectory && entry.uncompressedSize > 0 && entry.compressedSize === 0) {
      scan.problems.push(`压缩体积异常：${entry.name}`);
    }
    if (isArchiveMetadata(trimmed)) { continue; }
    const relative = scan.commonRoot.length > 0 && trimmed.startsWith(`${scan.commonRoot}/`)
      ? trimmed.slice(scan.commonRoot.length + 1)
      : trimmed;
    if (relative === 'manifest.json') {
      hasManifest = true;
    }
  }

  if (!hasManifest) {
    scan.problems.push(`插件包根目录缺少 manifest.json（包内顶层：${topLevelSummary(scan)}）`);
  }

  if (scan.commonRoot.length > 0) {
    const prefix = `${scan.commonRoot}/`;
    for (const entry of scan.entries) {
      const trimmed = entry.name.replace(/\/+$/, '');
      if (!trimmed || isArchiveMetadata(trimmed) || trimmed === scan.commonRoot) { continue; }
      if (!trimmed.startsWith(prefix)) {
        scan.problems.push(`插件包结构异常：${entry.name} 不在插件文件夹 ${scan.commonRoot}/ 内`);
        break;
      }
    }
  }

  scan.ok = scan.problems.length === 0;
  return scan;
}

export function extractPluginZip(buf: Buffer, scan: PluginZipScan, targetDir: string): void {
  if (!scan.ok) {
    raisePluginError(PluginErrorCode.INSTALL_REJECTED, scan.problems[0] || 'ZIP 校验失败');
  }
  const destRoot = resolve(targetDir);
  mkdirSync(destRoot, { recursive: true });
  let totalWritten = 0;

  for (const entry of scan.entries) {
    const trimmed = entry.name.replace(/\/+$/, '');
    if (!trimmed || isArchiveMetadata(trimmed)) { continue; }
    if (scan.commonRoot.length > 0 && trimmed === scan.commonRoot) { continue; }
    const rel = relativeZipEntryName(scan, entry);
    if (!rel) { continue; }

    const outPath = resolve(destRoot, rel);
    if (outPath !== destRoot && !outPath.startsWith(destRoot + sep)) {
      raisePluginError(PluginErrorCode.INSTALL_REJECTED, `路径越界：${entry.name}`);
    }

    if (entry.isDirectory) {
      mkdirSync(outPath, { recursive: true });
      continue;
    }

    const offset = entry.localHeaderOffset;
    if (offset + 30 > buf.length || buf.readUInt32LE(offset) !== LOCAL_SIGNATURE) {
      raisePluginError(PluginErrorCode.INSTALL_REJECTED, `本地文件头损坏：${entry.name}`);
    }
    const localNameLen = buf.readUInt16LE(offset + 26);
    const localExtraLen = buf.readUInt16LE(offset + 28);
    const dataStart = offset + 30 + localNameLen + localExtraLen;
    const dataEnd = dataStart + entry.compressedSize;
    if (dataStart < 0 || dataEnd > buf.length) {
      raisePluginError(PluginErrorCode.INSTALL_REJECTED, `条目数据越界：${entry.name}`);
    }

    const compressed = buf.subarray(dataStart, dataEnd);
    let data: Buffer;
    if (entry.method === 0) {
      data = compressed;
    } else if (entry.method === 8) {
      try {
        const remainingQuota = PluginLimits.MAX_ZIP_BYTES - totalWritten;
        const maxOut = Math.max(0, Math.min(remainingQuota, entry.uncompressedSize + 4096));
        data = inflateRawSync(compressed, { maxOutputLength: maxOut });
      } catch (error) {
        raisePluginError(PluginErrorCode.INSTALL_REJECTED, `条目解压失败：${entry.name}`);
      }
    } else {
      raisePluginError(PluginErrorCode.INSTALL_REJECTED, `不支持的压缩方式 ${entry.method}：${entry.name}`);
    }

    totalWritten += data.length;
    if (totalWritten > PluginLimits.MAX_ZIP_BYTES) {
      raisePluginError(PluginErrorCode.INSTALL_REJECTED, '解压总大小超过安全上限');
    }

    mkdirSync(dirname(outPath), { recursive: true });
    writeFileSync(outPath, data);
  }
}

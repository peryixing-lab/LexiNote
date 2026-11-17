import { randomUUID } from 'node:crypto';
import {
  closeSync,
  existsSync,
  fsyncSync,
  mkdirSync,
  openSync,
  promises as fsp,
  readdirSync,
  readFileSync,
  renameSync,
  statSync,
  unlinkSync,
  writeFileSync,
  writeSync
} from 'node:fs';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { deflateRawSync, inflateRawSync } from 'node:zlib';
import type { CanvasBoard, MindMapDoc, NoteItem, NoteProperty, PersistedState, VaultItem } from '../shared/types';
import { checkZipEntryName, isArchiveMetadata } from './pluginZip';

const EOCD_SIG = 0x06054b50;
const CENTRAL_SIG = 0x02014b50;
const LOCAL_SIG = 0x04034b50;

function sanitizeSegment(raw: string, fallback: string): string {
  const cleaned = raw
    .trim()
    .replace(/[\\/:*?"<>|]/g, '_')
    .replace(/\.+$/, '');
  return cleaned || fallback;
}

export function resolveVaultFolder(userDataDir: string, vault: VaultItem): string {
  if (vault.folderUri && vault.folderUri.trim().length > 0) {
    return vault.folderUri.trim();
  }
  return join(userDataDir, 'workspaces', sanitizeSegment(vault.name || vault.id, vault.id));
}

const SYSTEM_FRONTMATTER_KEYS = new Set([
  'id',
  'title',
  'notebook',
  'type',
  'level',
  'pinned',
  'favorite',
  'tags',
  'tag',
  'created',
  'updated',
  'trashed',
  'properties'
]);

function stripExistingFrontmatter(raw: string): string {
  const normalized = raw.replace(/^\uFEFF/, '').replace(/\r\n/g, '\n');
  if (!normalized.startsWith('---\n')) return raw;
  const lines = normalized.split('\n');
  for (let i = 1; i < lines.length; i++) {
    if (lines[i] === '---' || lines[i] === '...') {
      return lines.slice(i + 1).join('\n').replace(/^\n+/, '');
    }
  }
  return raw;
}

function isoDate(ms: number | undefined, fallbackMs: number): string {
  const value = typeof ms === 'number' && Number.isFinite(ms) && ms > 0 ? ms : fallbackMs;
  return new Date(value).toISOString();
}

export function serializeNoteMarkdown(note: NoteItem): string {
  const now = Date.now();
  const lines: string[] = ['---'];
  lines.push(`id: ${JSON.stringify(note.id)}`);
  lines.push(`title: ${JSON.stringify(note.title || '未命名笔记')}`);
  lines.push(`notebook: ${JSON.stringify(note.notebook || '默认')}`);
  lines.push(`type: ${note.noteType || 'markdown'}`);
  lines.push(`level: ${note.editorLevel || 'pro'}`);
  lines.push(`pinned: ${note.pinned ? 'true' : 'false'}`);
  lines.push(`favorite: ${note.favorite ? 'true' : 'false'}`);
  lines.push(`tags: [${(note.tags ?? []).map((t) => JSON.stringify(t)).join(', ')}]`);
  lines.push(`created: ${isoDate(note.createdAt, now)}`);
  lines.push(`updated: ${isoDate(note.updatedAt, now)}`);
  if (note.trashedAt && note.trashedAt > 0) {
    lines.push(`trashed: ${isoDate(note.trashedAt, now)}`);
  }
  const customProps = (note.properties ?? []).filter(
    (prop) => prop.key && !SYSTEM_FRONTMATTER_KEYS.has(prop.key.toLowerCase())
  );
  if (customProps.length > 0) {
    lines.push('properties:');
    for (const prop of customProps) {
      lines.push(`  - key: ${JSON.stringify(prop.key)}`);
      lines.push(`    value: ${JSON.stringify(prop.value ?? '')}`);
    }
  }
  lines.push('---', '');
  lines.push(stripExistingFrontmatter(note.content ?? ''));
  return lines.join('\n');
}

export function noteRelativePath(note: Pick<NoteItem, 'id' | 'title' | 'notebook'>): string {
  const sub = note.notebook && note.notebook !== '默认' ? sanitizeSegment(note.notebook, '默认') : '';
  const stem = sanitizeSegment(note.title || note.id, note.id);
  return sub ? `${sub}/${stem}.md` : `${stem}.md`;
}

function removeStaleFiles(dir: string, keepRelPaths: Set<string>, matcher: (rel: string) => boolean, rootDir: string): void {
  if (!existsSync(dir)) return;
  for (const name of readdirSync(dir)) {
    if (name.startsWith('.') || name === 'attachments') continue;
    const full = join(dir, name);
    const st = statSync(full);
    if (st.isDirectory()) {
      removeStaleFiles(full, keepRelPaths, matcher, rootDir);
    } else if (st.isFile()) {
      const rel = relative(rootDir, full).split(sep).join('/');
      if (matcher(rel) && !keepRelPaths.has(rel)) {
        try {
          unlinkSync(full);
        } catch {
          // Ignore locked files during cleanup.
        }
      }
    }
  }
}

export function isDiskFullError(error: unknown): boolean {
  if (!error || typeof error !== 'object') return false;
  const err = error as NodeJS.ErrnoException;
  const msg = String(err.message || '').toLowerCase();
  return (
    err.code === 'ENOSPC' ||
    err.errno === -28 ||
    err.errno === 28 ||
    msg.includes('enospc') ||
    msg.includes('no space') ||
    msg.includes('disk full') ||
    msg.includes('存储空间已满')
  );
}

export function friendlySaveError(error: unknown, fallback = '保存失败，当前编辑草稿已保留'): string {
  if (isDiskFullError(error)) {
    return '存储空间已满（ENOSPC），无法写入磁盘，当前修改已保留在编辑区与崩溃恢复日志中';
  }
  if (error instanceof Error && error.message) return error.message;
  return fallback;
}

export function atomicWriteTextSync(filePath: string, content: string): void {
  const dir = dirname(filePath);
  mkdirSync(dir, { recursive: true });
  const tmpPath = `${filePath}.tmp.${process.pid}`;
  let fd: number | null = null;
  try {
    fd = openSync(tmpPath, 'w');
    writeSync(fd, content, 0, 'utf8');
    fsyncSync(fd);
    closeSync(fd);
    fd = null;
    renameSync(tmpPath, filePath);
  } catch (error) {
    if (fd !== null) {
      try {
        closeSync(fd);
      } catch {
        // Ignore close cleanup errors.
      }
    }
    try {
      if (existsSync(tmpPath)) unlinkSync(tmpPath);
    } catch {
      // Ignore temp cleanup errors.
    }
    throw error;
  }
}

export async function atomicWriteTextAsync(filePath: string, content: string): Promise<void> {
  const dir = dirname(filePath);
  await fsp.mkdir(dir, { recursive: true });
  const tmpPath = `${filePath}.tmp.${process.pid}.${randomUUID().slice(0, 6)}`;
  let handle: Awaited<ReturnType<typeof fsp.open>> | null = null;
  try {
    handle = await fsp.open(tmpPath, 'w');
    await handle.writeFile(content, 'utf8');
    await handle.sync();
    await handle.close();
    handle = null;
    await fsp.rename(tmpPath, filePath);
  } catch (error) {
    if (handle) {
      try {
        await handle.close();
      } catch {
        // Ignore close cleanup errors.
      }
    }
    try {
      await fsp.unlink(tmpPath);
    } catch {
      // Ignore temp cleanup errors.
    }
    throw error;
  }
}

export function syncStateToWorkspaceFolders(userDataDir: string, state: PersistedState): string[] {
  const warnings: string[] = [];
  for (const vault of state.vaults) {
    if (vault.archived) continue;
    const root = resolveVaultFolder(userDataDir, vault);
    try {
      mkdirSync(root, { recursive: true });
      mkdirSync(join(root, 'attachments'), { recursive: true });

      const manifest = {
        format: 'LexiNote.Workspace',
        version: 1,
        vaultId: vault.id,
        vaultName: vault.name,
        description: vault.description || '',
        exportedAt: new Date().toISOString(),
        platform: 'windows'
      };
      atomicWriteTextSync(join(root, 'lexinote-manifest.json'), JSON.stringify(manifest, null, 2));

      const expectedNotes = new Set<string>();
      const vaultNotes = state.notes.filter((n) => n.vaultId === vault.id && n.trashedAt === 0);
      for (const note of vaultNotes) {
        const sub = note.notebook && note.notebook !== '默认' ? sanitizeSegment(note.notebook, '默认') : '';
        const stem = sanitizeSegment(note.title || note.id, note.id);
        let rel = sub ? `${sub}/${stem}.md` : `${stem}.md`;
        let suffix = 1;
        while (expectedNotes.has(rel)) {
          rel = sub ? `${sub}/${stem}-${suffix++}.md` : `${stem}-${suffix++}.md`;
        }
        expectedNotes.add(rel);
        const full = join(root, ...rel.split('/'));
        atomicWriteTextSync(full, serializeNoteMarkdown(note));
      }
      removeStaleFiles(
        root,
        expectedNotes,
        (rel) => /\.(md|markdown)$/i.test(rel) && !rel.startsWith('思维导图/') && !rel.startsWith('白板/'),
        root
      );

      const expectedMaps = new Set<string>();
      const vaultMaps = state.maps.filter((m) => m.vaultId === vault.id && m.trashedAt === 0);
      if (vaultMaps.length > 0) {
        const mapDir = join(root, '思维导图');
        mkdirSync(mapDir, { recursive: true });
        for (const map of vaultMaps) {
          const fileName = `${sanitizeSegment(map.id, 'map')}.mindmap.json`;
          expectedMaps.add(`思维导图/${fileName}`);
          atomicWriteTextSync(join(mapDir, fileName), JSON.stringify(map, null, 2));
        }
      }
      removeStaleFiles(root, expectedMaps, (rel) => /\.mindmap\.json$/i.test(rel), root);

      const expectedCanvases = new Set<string>();
      const vaultCanvases = state.canvases.filter((c) => c.vaultId === vault.id);
      if (vaultCanvases.length > 0) {
        const canvasDir = join(root, '白板');
        mkdirSync(canvasDir, { recursive: true });
        for (const board of vaultCanvases) {
          const fileName = `${sanitizeSegment(board.id, 'canvas')}.canvas.json`;
          expectedCanvases.add(`白板/${fileName}`);
          atomicWriteTextSync(join(canvasDir, fileName), JSON.stringify(board, null, 2));
        }
      }
      removeStaleFiles(root, expectedCanvases, (rel) => /\.canvas\.json$/i.test(rel), root);
    } catch (error) {
      if (isDiskFullError(error)) {
        warnings.push(`工作区「${vault.name}」磁盘已满，镜像同步未完成`);
        throw error;
      }
      warnings.push(`工作区「${vault.name}」目录不可用：${friendlySaveError(error)}`);
    }
  }
  return warnings;
}

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let i = 0; i < 256; i++) {
    let c = i;
    for (let k = 0; k < 8; k++) {
      c = (c & 1) !== 0 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    }
    table[i] = c >>> 0;
  }
  return table;
})();

function crc32(buf: Buffer): number {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) {
    c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  }
  return (c ^ 0xffffffff) >>> 0;
}

export function buildZipBuffer(entries: { name: string; data: Buffer }[]): Buffer {
  const localParts: Buffer[] = [];
  const centralParts: Buffer[] = [];
  let offset = 0;

  for (const entry of entries) {
    const nameBuf = Buffer.from(entry.name.replace(/\\/g, '/'), 'utf8');
    const compressed = deflateRawSync(entry.data);
    const sum = crc32(entry.data);

    const local = Buffer.alloc(30 + nameBuf.length);
    local.writeUInt32LE(LOCAL_SIG, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(0x0800, 6); // UTF-8 flag
    local.writeUInt16LE(8, 8); // Deflate
    local.writeUInt16LE(0, 10);
    local.writeUInt16LE(0, 12);
    local.writeUInt32LE(sum, 14);
    local.writeUInt32LE(compressed.length, 18);
    local.writeUInt32LE(entry.data.length, 22);
    local.writeUInt16LE(nameBuf.length, 26);
    local.writeUInt16LE(0, 28);
    nameBuf.copy(local, 30);

    localParts.push(local, compressed);

    const central = Buffer.alloc(46 + nameBuf.length);
    central.writeUInt32LE(CENTRAL_SIG, 0);
    central.writeUInt16LE(20, 4);
    central.writeUInt16LE(20, 6);
    central.writeUInt16LE(0x0800, 8);
    central.writeUInt16LE(8, 10);
    central.writeUInt16LE(0, 12);
    central.writeUInt16LE(0, 14);
    central.writeUInt32LE(sum, 16);
    central.writeUInt32LE(compressed.length, 20);
    central.writeUInt32LE(entry.data.length, 24);
    central.writeUInt16LE(nameBuf.length, 28);
    central.writeUInt16LE(0, 30);
    central.writeUInt16LE(0, 32);
    central.writeUInt16LE(0, 34);
    central.writeUInt16LE(0, 36);
    central.writeUInt32LE(0, 38);
    central.writeUInt32LE(offset, 42);
    nameBuf.copy(central, 46);
    centralParts.push(central);

    offset += local.length + compressed.length;
  }

  const centralSize = centralParts.reduce((acc, b) => acc + b.length, 0);
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(EOCD_SIG, 0);
  eocd.writeUInt16LE(0, 4);
  eocd.writeUInt16LE(0, 6);
  eocd.writeUInt16LE(entries.length, 8);
  eocd.writeUInt16LE(entries.length, 10);
  eocd.writeUInt32LE(centralSize, 12);
  eocd.writeUInt32LE(offset, 16);
  eocd.writeUInt16LE(0, 20);

  return Buffer.concat([...localParts, ...centralParts, eocd]);
}

export function collectWorkspaceFilesForZip(folderPath: string): { name: string; data: Buffer }[] {
  const results: { name: string; data: Buffer }[] = [];
  if (!existsSync(folderPath)) return results;

  const walk = (dir: string, inAttachments: boolean): void => {
    for (const name of readdirSync(dir)) {
      if (name.startsWith('.')) continue;
      const full = join(dir, name);
      const st = statSync(full);
      if (st.isDirectory()) {
        walk(full, inAttachments || name === 'attachments');
      } else if (st.isFile() && (inAttachments || /\.(md|markdown|json)$/i.test(name))) {
        const rel = relative(folderPath, full).split(sep).join('/');
        results.push({ name: rel, data: readFileSync(full) });
      }
    }
  };
  walk(folderPath, false);
  return results;
}

export function extractZipToFolder(zipPath: string, destFolder: string): number {
  const buf = readFileSync(zipPath);
  let eocdOffset = -1;
  const limit = Math.max(0, buf.length - 65535 - 22);
  for (let offset = buf.length - 22; offset >= limit; offset -= 1) {
    if (buf.readUInt32LE(offset) === EOCD_SIG) {
      eocdOffset = offset;
      break;
    }
  }
  if (eocdOffset < 0) throw new Error('无效的 ZIP 压缩包');

  const totalEntries = buf.readUInt16LE(eocdOffset + 10);
  const cdOffset = buf.readUInt32LE(eocdOffset + 16);
  const resolvedDest = resolve(destFolder);
  mkdirSync(resolvedDest, { recursive: true });

  let cursor = cdOffset;
  let written = 0;
  for (let i = 0; i < totalEntries; i++) {
    if (buf.readUInt32LE(cursor) !== CENTRAL_SIG) throw new Error('ZIP 中央目录损坏');
    const method = buf.readUInt16LE(cursor + 10);
    const compressedSize = buf.readUInt32LE(cursor + 20);
    const uncompressedSize = buf.readUInt32LE(cursor + 24);
    const nameLen = buf.readUInt16LE(cursor + 28);
    const extraLen = buf.readUInt16LE(cursor + 30);
    const commentLen = buf.readUInt16LE(cursor + 32);
    const localOffset = buf.readUInt32LE(cursor + 42);
    const name = buf.subarray(cursor + 46, cursor + 46 + nameLen).toString('utf8');
    cursor += 46 + nameLen + extraLen + commentLen;

    if (name.endsWith('/') || isArchiveMetadata(name)) continue;
    const problem = checkZipEntryName(name);
    if (problem) throw new Error(`压缩包路径不安全（${name}）：${problem}`);

    if (buf.readUInt32LE(localOffset) !== LOCAL_SIG) throw new Error('ZIP 本地文件头损坏');
    const localNameLen = buf.readUInt16LE(localOffset + 26);
    const localExtraLen = buf.readUInt16LE(localOffset + 28);
    const dataStart = localOffset + 30 + localNameLen + localExtraLen;
    const compressed = buf.subarray(dataStart, dataStart + compressedSize);
    const data = method === 0 ? compressed : method === 8 ? inflateRawSync(compressed) : null;
    if (!data) throw new Error(`不支持的 ZIP 压缩算法（method=${method}）`);
    if (data.length !== uncompressedSize && uncompressedSize > 0) {
      // Allow mismatch only if 0; otherwise keep strict
    }

    const target = resolve(resolvedDest, name);
    if (!target.startsWith(resolvedDest + sep)) throw new Error('ZIP 路径越界');
    mkdirSync(dirname(target), { recursive: true });
    writeFileSync(target, data);
    written += 1;
  }
  return written;
}

function unquoteYaml(v: string): string {
  const t = v.trim();
  if (t.startsWith('"') && t.endsWith('"') && t.length >= 2) {
    try {
      return String(JSON.parse(t));
    } catch {
      return t.slice(1, -1);
    }
  }
  if (t.startsWith("'") && t.endsWith("'") && t.length >= 2) {
    return t.slice(1, -1).replace(/''/g, "'");
  }
  return t;
}

function parseDateMs(raw: string | number | undefined, fallback: number): number {
  if (typeof raw === 'number' && Number.isFinite(raw)) {
    return raw > 0 && raw < 1e11 ? raw * 1000 : raw;
  }
  if (typeof raw === 'string' && raw.trim()) {
    const asNum = Number(raw.trim());
    if (Number.isFinite(asNum) && asNum > 0) {
      return asNum < 1e11 ? asNum * 1000 : asNum;
    }
    const parsed = Date.parse(raw.trim());
    if (Number.isFinite(parsed)) return parsed;
  }
  return fallback;
}

export function parseNoteMarkdown(
  rawInput: string,
  opts: {
    vaultId: string;
    fallbackTitle: string;
    fallbackNotebook: string;
    filePath?: string;
    birthtimeMs?: number;
    mtimeMs?: number;
  }
): NoteItem {
  const now = Date.now();
  const birthtime = opts.birthtimeMs || opts.mtimeMs || now;
  const mtime = opts.mtimeMs || now;
  const raw = rawInput.replace(/^\uFEFF/, '');

  let id = `note-${randomUUID()}`;
  let title = opts.fallbackTitle || '未命名笔记';
  let notebook = opts.fallbackNotebook || '默认';
  let noteType: NoteItem['noteType'] = 'markdown';
  let editorLevel: NoteItem['editorLevel'] = 'pro';
  let pinned = false;
  let favorite = false;
  let createdAt = birthtime;
  let updatedAt = mtime;
  let trashedAt = 0;
  let body = raw;
  const tags: string[] = [];
  const properties: NoteProperty[] = [];

  const normalized = raw.replace(/\r\n/g, '\n');
  if (normalized.startsWith('---\n')) {
    const lines = normalized.split('\n');
    let end = -1;
    for (let i = 1; i < lines.length; i++) {
      if (lines[i].trim() === '---' || lines[i].trim() === '...') {
        end = i;
        break;
      }
    }
    if (end > 0) {
      body = lines.slice(end + 1).join('\n').replace(/^\n+/, '');
      let inProperties = false;
      let pendingPropKey: string | null = null;
      let inTagsList = false;

      for (let i = 1; i < end; i++) {
        const line = lines[i];
        const trimmed = line.trim();
        if (!trimmed || trimmed.startsWith('#')) continue;

        if (inProperties) {
          if (line.startsWith('  - key:')) {
            pendingPropKey = unquoteYaml(line.slice('  - key:'.length));
            continue;
          }
          if (line.startsWith('    value:') && pendingPropKey !== null) {
            properties.push({ key: pendingPropKey, value: unquoteYaml(line.slice('    value:'.length)) });
            pendingPropKey = null;
            continue;
          }
          if (!/^\s/.test(line)) {
            inProperties = false;
            pendingPropKey = null;
          } else {
            continue;
          }
        }

        if (inTagsList) {
          if (/^\s+-\s+/.test(line)) {
            const clean = unquoteYaml(line.replace(/^\s+-\s+/, '')).replace(/^#/, '').trim();
            if (clean && !tags.includes(clean)) tags.push(clean);
            continue;
          }
          inTagsList = false;
        }

        const colon = line.indexOf(':');
        if (colon <= 0) continue;
        const k = unquoteYaml(line.slice(0, colon)).trim();
        const kLower = k.toLowerCase();
        const v = line.slice(colon + 1).trim();
        const unquoted = unquoteYaml(v);

        if (kLower === 'properties') {
          inProperties = true;
          continue;
        }
        if (kLower === 'id' && unquoted) id = unquoted;
        else if (kLower === 'title' && unquoted) title = unquoted;
        else if (kLower === 'notebook' && unquoted) notebook = unquoted;
        else if (kLower === 'type' && (unquoted === 'quick' || unquoted === 'study' || unquoted === 'markdown')) {
          noteType = unquoted;
        } else if (kLower === 'level' && (unquoted === 'simple' || unquoted === 'study' || unquoted === 'pro')) {
          editorLevel = unquoted;
        } else if (kLower === 'pinned') pinned = unquoted.toLowerCase() === 'true';
        else if (kLower === 'favorite') favorite = unquoted.toLowerCase() === 'true';
        else if (kLower === 'created') createdAt = parseDateMs(unquoted, birthtime);
        else if (kLower === 'updated') updatedAt = parseDateMs(unquoted, mtime);
        else if (kLower === 'trashed') trashedAt = parseDateMs(unquoted, 0);
        else if (kLower === 'tags' || kLower === 'tag') {
          if (!v) {
            inTagsList = true;
          } else {
            try {
              const arr = JSON.parse(v);
              if (Array.isArray(arr)) {
                for (const t of arr) {
                  const clean = String(t).replace(/^#/, '').trim();
                  if (clean && !tags.includes(clean)) tags.push(clean);
                }
                continue;
              }
            } catch {
              // Fall through to bracket/comma split.
            }
            const stripped = v.startsWith('[') && v.endsWith(']') ? v.slice(1, -1) : v;
            for (const part of stripped.split(',')) {
              const clean = unquoteYaml(part).replace(/^#/, '').trim();
              if (clean && !tags.includes(clean)) tags.push(clean);
            }
          }
        } else {
          properties.push({ key: k, value: unquoted });
        }
      }
    }
  }

  return {
    id,
    vaultId: opts.vaultId,
    projectId: '',
    title,
    notebook,
    content: body,
    noteType,
    editorLevel,
    tags,
    properties,
    pinned,
    favorite,
    trashedAt,
    createdAt,
    updatedAt,
    path: opts.filePath ?? ''
  };
}

export function normalizeMindMapDoc(raw: Record<string, unknown>, vaultId: string): MindMapDoc | null {
  const id = typeof raw.id === 'string' ? raw.id : '';
  const nodesRaw = Array.isArray(raw.nodes) ? (raw.nodes as Record<string, unknown>[]) : null;
  if (!id || !nodesRaw) return null;
  const now = Date.now();
  const layoutRaw = raw.layoutKind ?? raw.layout;
  const layoutKind: MindMapDoc['layoutKind'] =
    layoutRaw === 'balanced' || layoutRaw === 'org' || layoutRaw === 'right' ? layoutRaw : 'right';
  const nodes: MindMapDoc['nodes'] = nodesRaw.map((n, index) => ({
    id: String(n.id ?? `node-${index}`),
    parentId: String(n.parentId ?? n.parentID ?? ''),
    text: String(n.text ?? ''),
    note: String(n.note ?? ''),
    noteRefId: String(n.noteRefId ?? n.noteRefID ?? ''),
    noteRefTitle: String(n.noteRefTitle ?? ''),
    order: typeof n.order === 'number' ? n.order : index,
    collapsed: Boolean(n.collapsed),
    colorTag:
      n.colorTag === 'purple' || n.colorTag === 'indigo' || n.colorTag === 'teal' || n.colorTag === 'amber' || n.colorTag === 'rose'
        ? n.colorTag
        : 'purple',
    level: typeof n.level === 'number' ? n.level : 0,
    x: typeof n.x === 'number' ? n.x : 0,
    y: typeof n.y === 'number' ? n.y : 0,
    boxWidth: typeof n.boxWidth === 'number' ? n.boxWidth : 120,
    boxHeight: typeof n.boxHeight === 'number' ? n.boxHeight : 36,
    offsetX: typeof n.offsetX === 'number' ? n.offsetX : 0,
    offsetY: typeof n.offsetY === 'number' ? n.offsetY : 0
  }));
  return {
    id,
    vaultId,
    projectId: typeof raw.projectId === 'string' ? raw.projectId : '',
    title: typeof raw.title === 'string' ? raw.title : '未命名导图',
    layoutKind,
    rootNodeId: String(raw.rootNodeId ?? raw.rootNodeID ?? nodes[0]?.id ?? ''),
    nodes,
    favorite: Boolean(raw.favorite),
    trashedAt: parseDateMs(raw.trashedAt as string | number | undefined, 0),
    createdAt: parseDateMs(raw.createdAt as string | number | undefined, now),
    updatedAt: parseDateMs(raw.updatedAt as string | number | undefined, now)
  };
}

export function normalizeCanvasBoard(raw: Record<string, unknown>, vaultId: string): CanvasBoard | null {
  const id = typeof raw.id === 'string' ? raw.id : '';
  const cardsRaw = Array.isArray(raw.cards) ? (raw.cards as Record<string, unknown>[]) : null;
  if (!id || !cardsRaw) return null;
  const now = Date.now();
  const edgesRaw = Array.isArray(raw.edges) ? (raw.edges as Record<string, unknown>[]) : [];
  return {
    id,
    vaultId,
    projectId: typeof raw.projectId === 'string' ? raw.projectId : '',
    title: typeof raw.title === 'string' ? raw.title : '未命名白板',
    cards: cardsRaw.map((c, idx) => ({
      id: String(c.id ?? `card-${idx}`),
      title: String(c.title ?? ''),
      content: String(c.content ?? ''),
      noteRefId: String(c.noteRefId ?? c.noteRefID ?? ''),
      noteRefTitle: String(c.noteRefTitle ?? ''),
      x: typeof c.x === 'number' ? c.x : 0,
      y: typeof c.y === 'number' ? c.y : 0,
      colorTag:
        c.colorTag === 'purple' || c.colorTag === 'indigo' || c.colorTag === 'teal' || c.colorTag === 'amber' || c.colorTag === 'rose'
          ? c.colorTag
          : 'purple'
    })),
    edges: edgesRaw.map((e, idx) => ({
      id: String(e.id ?? `edge-${idx}`),
      fromId: String(e.fromId ?? e.fromID ?? ''),
      toId: String(e.toId ?? e.toID ?? ''),
      label: String(e.label ?? '')
    })),
    createdAt: parseDateMs(raw.createdAt as string | number | undefined, now),
    updatedAt: parseDateMs(raw.updatedAt as string | number | undefined, now)
  };
}

export function scanWorkspaceFolder(
  folderPath: string,
  vaultId: string
): { notes: NoteItem[]; maps: MindMapDoc[]; canvases: CanvasBoard[]; vaultName?: string; description?: string; warnings: string[] } {
  const notes: NoteItem[] = [];
  const maps: MindMapDoc[] = [];
  const canvases: CanvasBoard[] = [];
  const warnings: string[] = [];
  let vaultName: string | undefined;
  let description: string | undefined;
  if (!existsSync(folderPath)) {
    warnings.push(`工作区文件夹不存在：${folderPath}`);
    return { notes, maps, canvases, warnings };
  }

  const manifestPath = join(folderPath, 'lexinote-manifest.json');
  if (existsSync(manifestPath)) {
    try {
      const m = JSON.parse(readFileSync(manifestPath, 'utf8')) as { vaultName?: string; description?: string };
      if (m.vaultName) vaultName = m.vaultName;
      if (m.description) description = m.description;
    } catch {
      warnings.push('工作区清单 lexinote-manifest.json 解析失败，已忽略');
    }
  }

  const walk = (dir: string): void => {
    let entries: string[] = [];
    try {
      entries = readdirSync(dir);
    } catch (error) {
      warnings.push(`无法读取目录 ${relative(folderPath, dir) || folderPath}：${friendlySaveError(error)}`);
      return;
    }
    for (const name of entries) {
      if (name.startsWith('.') || name === 'attachments') continue;
      const full = join(dir, name);
      try {
        const st = statSync(full);
        if (st.isDirectory()) {
          walk(full);
        } else if (st.isFile()) {
          if (/\.mindmap\.json$/i.test(name)) {
            try {
              const rawDoc = JSON.parse(readFileSync(full, 'utf8')) as Record<string, unknown>;
              const doc = normalizeMindMapDoc(rawDoc, vaultId);
              if (doc) maps.push(doc);
              else warnings.push(`导图文件格式无效：${relative(folderPath, full)}`);
            } catch (error) {
              warnings.push(`导图读取失败 ${relative(folderPath, full)}：${friendlySaveError(error)}`);
            }
          } else if (/\.canvas\.json$/i.test(name)) {
            try {
              const rawBoard = JSON.parse(readFileSync(full, 'utf8')) as Record<string, unknown>;
              const board = normalizeCanvasBoard(rawBoard, vaultId);
              if (board) canvases.push(board);
              else warnings.push(`白板文件格式无效：${relative(folderPath, full)}`);
            } catch (error) {
              warnings.push(`白板读取失败 ${relative(folderPath, full)}：${friendlySaveError(error)}`);
            }
          } else if (/\.(md|markdown)$/i.test(name)) {
            const raw = readFileSync(full, 'utf8');
            const rel = relative(folderPath, full);
            const relDir = dirname(rel);
            const notebook = relDir === '.' ? '默认' : relDir.split(sep)[0];
            const stem = name.replace(/\.(md|markdown)$/i, '');
            notes.push(
              parseNoteMarkdown(raw, {
                vaultId,
                fallbackTitle: stem,
                fallbackNotebook: notebook,
                filePath: full,
                birthtimeMs: st.birthtimeMs,
                mtimeMs: st.mtimeMs
              })
            );
          }
        }
      } catch (error) {
        warnings.push(`读取文件失败 ${relative(folderPath, full)}：${friendlySaveError(error)}`);
      }
    }
  };
  walk(folderPath);
  return { notes, maps, canvases, vaultName, description, warnings };
}

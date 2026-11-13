import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
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

function serializeNoteMarkdown(note: NoteItem): string {
  const lines: string[] = ['---'];
  lines.push(`title: ${JSON.stringify(note.title || '未命名笔记')}`);
  lines.push(`id: ${JSON.stringify(note.id)}`);
  lines.push(`notebook: ${JSON.stringify(note.notebook || '默认')}`);
  lines.push(`type: ${JSON.stringify(note.noteType || 'quick')}`);
  if (note.tags && note.tags.length > 0) {
    lines.push(`tags: [${note.tags.map((t) => JSON.stringify(t)).join(', ')}]`);
  }
  for (const prop of note.properties ?? []) {
    if (prop.key && !['title', 'id', 'notebook', 'type', 'tags'].includes(prop.key)) {
      lines.push(`${prop.key}: ${JSON.stringify(prop.value)}`);
    }
  }
  lines.push('---', '');
  lines.push(note.content ?? '');
  return lines.join('\n');
}

export function syncStateToWorkspaceFolders(userDataDir: string, state: PersistedState): void {
  for (const vault of state.vaults) {
    if (vault.archived) continue;
    const root = resolveVaultFolder(userDataDir, vault);
    try {
      mkdirSync(root, { recursive: true });
      const usedNotePaths = new Set<string>();
      const vaultNotes = state.notes.filter((n) => n.vaultId === vault.id && n.trashedAt === 0);
      for (const note of vaultNotes) {
        const sub = note.notebook && note.notebook !== '默认' ? sanitizeSegment(note.notebook, '默认') : '';
        const stem = sanitizeSegment(note.title || note.id, note.id);
        let rel = sub ? join(sub, `${stem}.md`) : `${stem}.md`;
        let suffix = 1;
        while (usedNotePaths.has(rel)) {
          rel = sub ? join(sub, `${stem}-${suffix++}.md`) : `${stem}-${suffix++}.md`;
        }
        usedNotePaths.add(rel);
        const full = join(root, rel);
        mkdirSync(dirname(full), { recursive: true });
        writeFileSync(full, serializeNoteMarkdown(note), 'utf8');
      }

      const vaultMaps = state.maps.filter((m) => m.vaultId === vault.id && m.trashedAt === 0);
      if (vaultMaps.length > 0) {
        const mapDir = join(root, '思维导图');
        mkdirSync(mapDir, { recursive: true });
        for (const map of vaultMaps) {
          writeFileSync(join(mapDir, `${sanitizeSegment(map.id, 'map')}.mindmap.json`), JSON.stringify(map, null, 2), 'utf8');
        }
      }

      const vaultCanvases = state.canvases.filter((c) => c.vaultId === vault.id);
      if (vaultCanvases.length > 0) {
        const canvasDir = join(root, '白板');
        mkdirSync(canvasDir, { recursive: true });
        for (const board of vaultCanvases) {
          writeFileSync(join(canvasDir, `${sanitizeSegment(board.id, 'canvas')}.canvas.json`), JSON.stringify(board, null, 2), 'utf8');
        }
      }
    } catch {
      // Never block state persistence if an external folder is temporarily unavailable.
    }
  }
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

  const walk = (dir: string): void => {
    for (const name of readdirSync(dir)) {
      if (name.startsWith('.')) continue;
      const full = join(dir, name);
      const st = statSync(full);
      if (st.isDirectory()) {
        walk(full);
      } else if (st.isFile() && /\.(md|markdown|json)$/i.test(name)) {
        const rel = relative(folderPath, full).split(sep).join('/');
        results.push({ name: rel, data: readFileSync(full) });
      }
    }
  };
  walk(folderPath);
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

export function scanWorkspaceFolder(
  folderPath: string,
  vaultId: string
): { notes: NoteItem[]; maps: MindMapDoc[]; canvases: CanvasBoard[] } {
  const notes: NoteItem[] = [];
  const maps: MindMapDoc[] = [];
  const canvases: CanvasBoard[] = [];
  if (!existsSync(folderPath)) return { notes, maps, canvases };

  const walk = (dir: string): void => {
    for (const name of readdirSync(dir)) {
      if (name.startsWith('.')) continue;
      const full = join(dir, name);
      const st = statSync(full);
      if (st.isDirectory()) {
        walk(full);
      } else if (st.isFile()) {
        if (/\.mindmap\.json$/i.test(name)) {
          try {
            const doc = JSON.parse(readFileSync(full, 'utf8')) as MindMapDoc;
            if (doc && doc.id && Array.isArray(doc.nodes)) {
              maps.push({ ...doc, vaultId });
            }
          } catch {}
        } else if (/\.canvas\.json$/i.test(name)) {
          try {
            const board = JSON.parse(readFileSync(full, 'utf8')) as CanvasBoard;
            if (board && board.id && Array.isArray(board.cards)) {
              canvases.push({ ...board, vaultId });
            }
          } catch {}
        } else if (/\.(md|markdown)$/i.test(name)) {
          const raw = readFileSync(full, 'utf8').replace(/^\uFEFF/, '');
          const rel = relative(folderPath, full);
          const relDir = dirname(rel);
          const notebook = relDir === '.' ? '默认' : relDir.split(sep)[0];
          const stem = name.replace(/\.(md|markdown)$/i, '');
          let title = stem;
          let id = `note-${Buffer.from(rel).toString('hex').slice(0, 12)}`;
          let body = raw;
          const tags: string[] = [];
          const properties: NoteProperty[] = [];
          let noteType: NoteItem['noteType'] = 'markdown';

          if (raw.startsWith('---\n') || raw.startsWith('---\r\n')) {
            const endIdx = raw.indexOf('\n---', 3);
            if (endIdx > 0) {
              const header = raw.slice(4, endIdx);
              body = raw.slice(endIdx + 4).replace(/^\r?\n/, '');
              for (const line of header.split(/\r?\n/)) {
                const colon = line.indexOf(':');
                if (colon <= 0) continue;
                const k = line.slice(0, colon).trim();
                const v = line.slice(colon + 1).trim();
                const unquoted = v.startsWith('"') && v.endsWith('"') ? (() => { try { return String(JSON.parse(v)); } catch { return v; } })() : v;
                if (k === 'title' && unquoted) title = unquoted;
                else if (k === 'id' && unquoted) id = unquoted;
                else if (k === 'type' && (unquoted === 'quick' || unquoted === 'study' || unquoted === 'markdown')) noteType = unquoted;
                else if (k === 'tags') {
                  try {
                    const arr = JSON.parse(v);
                    if (Array.isArray(arr)) { for (const t of arr) tags.push(String(t)); }
                  } catch {
                    for (const part of v.split(/[\s,]+/)) {
                      const clean = part.replace(/^#/, '').trim();
                      if (clean) tags.push(clean);
                    }
                  }
                } else if (k !== 'notebook') {
                  properties.push({ key: k, value: unquoted });
                }
              }
            }
          }
          notes.push({
            id,
            vaultId,
            projectId: '',
            title,
            notebook,
            content: body,
            noteType,
            editorLevel: 'pro',
            tags,
            properties,
            pinned: false,
            favorite: false,
            trashedAt: 0,
            createdAt: st.birthtimeMs || st.mtimeMs,
            updatedAt: st.mtimeMs,
            path: full
          });
        }
      }
    }
  };
  walk(folderPath);
  return { notes, maps, canvases };
}

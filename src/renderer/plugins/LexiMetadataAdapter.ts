import type { NoteItem } from '../../shared/types';
import type {
  PluginHeadingCache,
  PluginLinkCache,
  PluginMetadataSnapshot
} from '../../shared/pluginTypes';
import {
  extractInlineTags,
  extractOutline,
  parseFrontmatter
} from '../core/markdown';

const SUPPORTED_METADATA_FIELDS = [
  'headings',
  'links',
  'embeds',
  'tags',
  'frontmatter',
  'properties.scalar'
];

const UNSUPPORTED_METADATA_FIELDS = [
  'sections',
  'blocks',
  'listItems',
  'footnotes',
  'frontmatter.nested',
  'codeBlocks'
];

export function computeContentHash(text: string): string {
  let hash = 0x811c9dc5;
  for (let i = 0; i < text.length; i += 1) {
    const code = text.charCodeAt(i);
    hash ^= code & 0xff;
    hash = Math.imul(hash, 0x01000193) >>> 0;
    hash ^= (code >>> 8) & 0xff;
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return `fnv1a-${hash.toString(16).padStart(8, '0')}`;
}

function lineOfOffset(content: string, offset: number): number {
  let line = 0;
  const limit = Math.min(offset, content.length);
  for (let i = 0; i < limit; i += 1) {
    if (content[i] === '\n') { line += 1; }
  }
  return line;
}

export function buildMetadataSnapshot(
  note: NoteItem,
  logicalPath: string,
  revision: number
): PluginMetadataSnapshot {
  const content = note.content || '';
  const headings: PluginHeadingCache[] = extractOutline(content).map((h) => ({
    heading: h.title,
    level: h.level,
    line: h.lineIndex,
    offset: 0
  }));

  const links: PluginLinkCache[] = [];
  const embeds: string[] = [];
  const linkPattern = /(!?)\[\[([^\[\]]+)\]\]/g;
  let match: RegExpExecArray | null = linkPattern.exec(content);
  while (match !== null) {
    const inner = match[2].trim();
    const pipe = inner.split('|');
    const left = pipe[0].trim();
    const hash = left.split('#');
    const target = hash[0].trim();
    const displayText = pipe.length > 1 ? pipe.slice(1).join('|').trim() : target;
    if (target) {
      if (match[1] === '!') {
        if (!embeds.includes(target)) { embeds.push(target); }
      } else {
        links.push({
          link: target,
          original: match[0],
          displayText,
          line: lineOfOffset(content, match.index)
        });
      }
    }
    match = linkPattern.exec(content);
  }

  const fm = parseFrontmatter(content);
  const frontmatterMatch = /^---\r?\n[\s\S]*?\r?\n---(?:\r?\n|$)/.exec(content);
  const rawFrontmatter = fm.properties.length > 0 && frontmatterMatch ? frontmatterMatch[0].trim() : '';

  const properties: Record<string, string> = {};
  for (const prop of fm.properties) {
    properties[prop.key] = prop.value;
  }

  const tags: string[] = [];
  for (const tag of fm.tags) {
    if (!tags.includes(tag)) { tags.push(tag); }
  }
  for (const tag of extractInlineTags(content)) {
    if (!tags.includes(tag)) { tags.push(tag); }
  }
  for (const tag of note.tags || []) {
    if (tag && !tags.includes(tag)) { tags.push(tag); }
  }

  return {
    fileId: note.id,
    path: logicalPath,
    version: revision,
    mtime: note.updatedAt,
    hash: computeContentHash(content),
    headings,
    links,
    embeds,
    tags,
    frontmatter: rawFrontmatter,
    properties,
    supportedFields: [...SUPPORTED_METADATA_FIELDS],
    unsupportedFields: [...UNSUPPORTED_METADATA_FIELDS],
    rawContent: content
  };
}

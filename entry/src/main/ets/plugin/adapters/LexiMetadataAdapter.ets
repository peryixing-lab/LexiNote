import { OutlineHeading } from '../../core/LexiModels';
import { NoteItem } from '../../core/LexiModels';
import { LexiFrontmatter } from '../../core/LexiFrontmatter';
import { MarkdownEngine, RawWikiLink } from '../../core/MarkdownEngine';
import { PluginHeadingCache, PluginLinkCache, PluginMetadataSnapshot } from '../model/PluginModels';

/**
 * Metadata subset derived from the existing parser (P13 partial).
 *
 * Only fields listed in `supportedFields` are meaningful. Nested YAML, block caches,
 * section offsets and CodeMirror extensions are reported as unsupported instead of being
 * filled with guesses.
 */
export class LexiMetadataAdapter {
  static readonly SUPPORTED: string[] = ['headings', 'links', 'embeds', 'tags', 'frontmatter', 'properties.scalar'];

  static contentHash(text: string): string {
    // FNV-1a over UTF-16 code units: stable, dependency free, and identical in ArkTS and JS.
    let hash = 0x811c9dc5;
    for (let index = 0; index < text.length; index++) {
      hash ^= text.charCodeAt(index) & 0xff;
      hash = (hash * 0x01000193) >>> 0;
      hash ^= (text.charCodeAt(index) >>> 8) & 0xff;
      hash = (hash * 0x01000193) >>> 0;
    }
    return `fnv1a-${hash.toString(16).padStart(8, '0')}`;
  }

  private static lineStarts(content: string): number[] {
    const starts: number[] = [0];
    for (let index = 0; index < content.length; index++) {
      if (content[index] === '\n') { starts.push(index + 1); }
    }
    return starts;
  }

  private static lineOf(content: string, offset: number): number {
    let line = 0;
    for (let index = 0; index < Math.min(offset, content.length); index++) {
      if (content[index] === '\n') { line++; }
    }
    return line;
  }

  static build(note: NoteItem, logicalPath: string, revision: number): PluginMetadataSnapshot {
    const snapshot = new PluginMetadataSnapshot();
    const content = note.content || '';
    snapshot.fileId = note.id;
    snapshot.path = logicalPath;
    snapshot.version = revision;
    snapshot.mtime = note.updatedAt;
    snapshot.hash = LexiMetadataAdapter.contentHash(content);
    snapshot.rawContent = content;
    snapshot.supportedFields = LexiMetadataAdapter.SUPPORTED.slice(0);
    snapshot.unsupportedFields = ['sections', 'blocks', 'listItems', 'footnotes', 'frontmatter.nested', 'codeBlocks'];

    for (const heading of MarkdownEngine.extractOutline(content)) {
      const cache = new PluginHeadingCache();
      cache.heading = heading.title;
      cache.level = heading.level;
      cache.line = heading.lineIndex;
      cache.offset = 0;
      snapshot.headings.push(cache);
    }

    const starts = LexiMetadataAdapter.lineStarts(content);
    const linkPattern = /(!?)\[\[([^\[\]]+)\]\]/g;
    let match: RegExpExecArray | null = linkPattern.exec(content);
    while (match !== null) {
      const inner = match[2].trim();
      const pipe = inner.split('|');
      const left = pipe[0].trim();
      const hash = left.split('#');
      const target = hash[0].trim();
      // The parser below must agree with LexiFrontmatter/MarkdownEngine for the same input.
      const parsed: RawWikiLink = new RawWikiLink();
      parsed.displayText = pipe.length > 1 ? pipe.slice(1).join('|').trim() : target;
      if (target.length > 0) {
        if (match[1] === '!') {
          if (!snapshot.embeds.includes(target)) { snapshot.embeds.push(target); }
        } else {
          const cache = new PluginLinkCache();
          cache.link = target;
          cache.original = match[0];
          cache.displayText = parsed.displayText;
          cache.line = LexiMetadataAdapter.lineOf(content, match.index);
          snapshot.links.push(cache);
        }
      }
      match = linkPattern.exec(content);
    }

    const frontmatter = LexiFrontmatter.parse(content);
    snapshot.frontmatter = frontmatter.hasFrontmatter ? frontmatter.rawHeader : '';
    for (const property of frontmatter.properties) {
      snapshot.properties.set(property.key, property.propValue);
    }
    const tags: string[] = [];
    for (const tag of frontmatter.tags) {
      if (!tags.includes(tag)) { tags.push(tag); }
    }
    for (const tag of MarkdownEngine.extractInlineTags(frontmatter.body)) {
      if (!tags.includes(tag)) { tags.push(tag); }
    }
    snapshot.tags = tags;
    if (frontmatter.hasFrontmatter) { snapshot.supportedFields.push('frontmatter.raw'); }
    if (starts.length > 1) { snapshot.supportedFields.push('lineIndex'); }
    return snapshot;
  }

  /** Heading offset used by `getHeadingPosition`; 0 when the heading is gone. */
  static headingOffset(content: string, heading: string, level: number): number {
    const headings: OutlineHeading[] = MarkdownEngine.extractOutline(content);
    const found = headings.find((item: OutlineHeading): boolean =>
      item.title === heading && (level <= 0 || item.level === level));
    if (!found) { return -1; }
    const starts = LexiMetadataAdapter.lineStarts(content);
    return starts[found.lineIndex] === undefined ? -1 : starts[found.lineIndex];
  }
}

'use strict';

const { normalizePath, basename, isObject, text } = require('./util');

const MAX_CITATIONS = 14;
const WIKILINK_RE = /\[\[([^\]\n|]+?)(?:\|([^\]\n]+?))?\]\]/g;
const MARKDOWN_LINK_RE = /\[([^\]\n]+)\]\(([^)\s]+)\)/g;
const EXTERNAL_URL_RE = /^(?:https?:|mailto:|tel:|data:)/i;

function stripMarkdownExt(value) {
  return String(value || '').replace(/\.md$/i, '');
}

function splitTargetFragment(rawTarget) {
  const cleaned = String(rawTarget || '').trim().replace(/^<|>$/g, '');
  if (!cleaned) {
    return { path: '', fragment: '' };
  }
  const hashIndex = cleaned.indexOf('#');
  if (hashIndex < 0) {
    return { path: cleaned, fragment: '' };
  }
  return {
    path: cleaned.slice(0, hashIndex).trim(),
    fragment: cleaned.slice(hashIndex + 1).trim()
  };
}

function decodeSafely(value) {
  try {
    return decodeURIComponent(value);
  } catch (_error) {
    return value;
  }
}

function noteNameFromRef(ref) {
  if (!isObject(ref)) {
    return '';
  }
  if (text(ref.name)) {
    return stripMarkdownExt(text(ref.name));
  }
  if (text(ref.path)) {
    return stripMarkdownExt(basename(text(ref.path)));
  }
  return '';
}

function buildLookupIndex(knownNotes, workspaceFiles) {
  const byPath = new Map();
  const byName = new Map();
  const ambiguousNames = new Set();

  function register(item, inContext) {
    if (!isObject(item) || !text(item.path)) {
      return;
    }
    const normPath = normalizePath(item.path);
    const keyPath = normPath.toLowerCase();
    const existing = byPath.get(keyPath);
    const merged = {
      id: text(item.id) || (existing ? existing.id : ''),
      path: normPath,
      name: text(item.name) || noteNameFromRef({ path: normPath }),
      inContext: Boolean(inContext || (existing && existing.inContext))
    };
    byPath.set(keyPath, merged);
    if (!normPath.endsWith('.md')) {
      byPath.set(`${keyPath}.md`, merged);
    } else {
      byPath.set(stripMarkdownExt(keyPath), merged);
    }

    const baseKey = stripMarkdownExt(basename(normPath)).toLowerCase();
    if (baseKey) {
      const prev = byName.get(baseKey);
      if (prev && prev.path !== merged.path) {
        ambiguousNames.add(baseKey);
      } else {
        byName.set(baseKey, merged);
      }
    }
  }

  if (Array.isArray(workspaceFiles)) {
    for (let i = 0; i < workspaceFiles.length; i += 1) {
      register(workspaceFiles[i], false);
    }
  }
  if (Array.isArray(knownNotes)) {
    for (let i = 0; i < knownNotes.length; i += 1) {
      register(knownNotes[i], true);
    }
  }

  return { byPath, byName, ambiguousNames };
}

function resolveTargetNote(rawTarget, index) {
  const decoded = decodeSafely(rawTarget);
  const { path: targetPath, fragment } = splitTargetFragment(decoded);
  if (!targetPath || EXTERNAL_URL_RE.test(targetPath)) {
    return null;
  }
  const normalized = normalizePath(targetPath);
  if (!normalized) {
    return null;
  }
  const lower = normalized.toLowerCase();
  const foundByPath = index.byPath.get(lower) || index.byPath.get(stripMarkdownExt(lower));
  if (foundByPath) {
    return { note: foundByPath, fragment };
  }
  const baseKey = stripMarkdownExt(basename(normalized)).toLowerCase();
  if (baseKey && !index.ambiguousNames.has(baseKey)) {
    const foundByName = index.byName.get(baseKey);
    if (foundByName) {
      return { note: foundByName, fragment };
    }
  }
  return null;
}

/**
 * Extracts verified note citations from `[label](path.md#frag)` and `[[note|label]]`
 * against context/read notes and vault files so hallucinated paths are filtered out.
 */
function extractCitations(markdownText, knownNotes = [], workspaceFiles = []) {
  const source = text(markdownText);
  const index = buildLookupIndex(knownNotes, workspaceFiles);
  const seen = new Set();
  const cited = [];

  function pushMatch(matched, labelText, sourceType) {
    if (!matched || cited.length >= MAX_CITATIONS) {
      return;
    }
    const key = `${matched.note.path}#${matched.fragment}`.toLowerCase();
    if (seen.has(key)) {
      return;
    }
    seen.add(key);
    cited.push({
      id: matched.note.id,
      path: matched.note.path,
      name: matched.note.name,
      label: text(labelText) || matched.note.name,
      fragment: matched.fragment,
      source: sourceType,
      inContext: matched.note.inContext
    });
  }

  if (source) {
    MARKDOWN_LINK_RE.lastIndex = 0;
    let match = MARKDOWN_LINK_RE.exec(source);
    while (match) {
      const matched = resolveTargetNote(match[2], index);
      pushMatch(matched, match[1], 'cited');
      match = MARKDOWN_LINK_RE.exec(source);
    }

    WIKILINK_RE.lastIndex = 0;
    match = WIKILINK_RE.exec(source);
    while (match) {
      const matched = resolveTargetNote(match[1], index);
      pushMatch(matched, match[2] || stripMarkdownExt(match[1]), 'cited');
      match = WIKILINK_RE.exec(source);
    }
  }

  return cited;
}

/**
 * Normalizes a persisted or freshly extracted citation list, falling back to
 * verified turn context sources when the model referenced nothing explicitly.
 */
function mergeCitationsWithContext(extracted, contextNotes = []) {
  const out = [];
  const seen = new Set();

  function append(item, fallbackSource) {
    if (!isObject(item) || !text(item.path) || out.length >= MAX_CITATIONS) {
      return;
    }
    const path = normalizePath(item.path);
    const fragment = text(item.fragment);
    const key = `${path}#${fragment}`.toLowerCase();
    if (seen.has(key)) {
      return;
    }
    seen.add(key);
    out.push({
      id: text(item.id),
      path,
      name: text(item.name) || noteNameFromRef({ path }),
      label: text(item.label) || text(item.name) || noteNameFromRef({ path }),
      fragment,
      source: text(item.source) || fallbackSource,
      inContext: item.inContext !== false
    });
  }

  if (Array.isArray(extracted)) {
    for (let i = 0; i < extracted.length; i += 1) {
      append(extracted[i], 'cited');
    }
  }

  if (out.length === 0 && Array.isArray(contextNotes)) {
    for (let i = 0; i < contextNotes.length; i += 1) {
      append(contextNotes[i], 'context');
    }
  }

  return out;
}

/** Resolves a clicked link target (`notes/a.md#L10` or `wiki:a`) to a vault/known note. */
function resolveCitationHref(href, knownNotes = [], workspaceFiles = []) {
  const raw = text(href).trim();
  if (!raw || EXTERNAL_URL_RE.test(raw)) {
    return null;
  }
  const normalizedHref = raw.startsWith('wiki:') ? raw.slice(5) : raw;
  const index = buildLookupIndex(knownNotes, workspaceFiles);
  return resolveTargetNote(normalizedHref, index);
}

module.exports = {
  MAX_CITATIONS,
  extractCitations,
  mergeCitationsWithContext,
  resolveCitationHref,
  splitTargetFragment
};

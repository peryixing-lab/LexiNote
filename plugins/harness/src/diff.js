'use strict';

const MAX_DP_CELLS = 160000;

/** Normalizes line endings and splits text into logical lines. */
function splitLines(text) {
  const source = typeof text === 'string' ? text.replace(/\r\n?/g, '\n') : '';
  if (source.length === 0) {
    return [];
  }
  return source.split('\n');
}

function lcsOps(aMid, bMid, oldOffset, newOffset) {
  const m = aMid.length;
  const n = bMid.length;
  if (m === 0 && n === 0) {
    return [];
  }
  if (m * n > MAX_DP_CELLS) {
    const ops = [];
    for (let i = 0; i < m; i += 1) {
      ops.push({ type: 'remove', oldLine: oldOffset + i + 1, newLine: 0, text: aMid[i] });
    }
    for (let j = 0; j < n; j += 1) {
      ops.push({ type: 'add', oldLine: 0, newLine: newOffset + j + 1, text: bMid[j] });
    }
    return ops;
  }

  const width = n + 1;
  const dp = new Int32Array((m + 1) * width);
  for (let i = m - 1; i >= 0; i -= 1) {
    const row = i * width;
    const nextRow = (i + 1) * width;
    const aLine = aMid[i];
    for (let j = n - 1; j >= 0; j -= 1) {
      if (aLine === bMid[j]) {
        dp[row + j] = dp[nextRow + j + 1] + 1;
      } else {
        const down = dp[nextRow + j];
        const right = dp[row + j + 1];
        dp[row + j] = down >= right ? down : right;
      }
    }
  }

  const ops = [];
  let i = 0;
  let j = 0;
  while (i < m && j < n) {
    if (aMid[i] === bMid[j]) {
      ops.push({ type: 'equal', oldLine: oldOffset + i + 1, newLine: newOffset + j + 1, text: aMid[i] });
      i += 1;
      j += 1;
    } else if (dp[(i + 1) * width + j] >= dp[i * width + (j + 1)]) {
      ops.push({ type: 'remove', oldLine: oldOffset + i + 1, newLine: 0, text: aMid[i] });
      i += 1;
    } else {
      ops.push({ type: 'add', oldLine: 0, newLine: newOffset + j + 1, text: bMid[j] });
      j += 1;
    }
  }
  while (i < m) {
    ops.push({ type: 'remove', oldLine: oldOffset + i + 1, newLine: 0, text: aMid[i] });
    i += 1;
  }
  while (j < n) {
    ops.push({ type: 'add', oldLine: 0, newLine: newOffset + j + 1, text: bMid[j] });
    j += 1;
  }
  return ops;
}

/** Computes line-level diff operations after trimming shared prefix and suffix lines. */
function computeLineDiff(beforeText, afterText) {
  const beforeLines = splitLines(beforeText);
  const afterLines = splitLines(afterText);
  const aLen = beforeLines.length;
  const bLen = afterLines.length;

  let prefix = 0;
  while (prefix < aLen && prefix < bLen && beforeLines[prefix] === afterLines[prefix]) {
    prefix += 1;
  }

  let suffix = 0;
  while (
    suffix < aLen - prefix &&
    suffix < bLen - prefix &&
    beforeLines[aLen - 1 - suffix] === afterLines[bLen - 1 - suffix]
  ) {
    suffix += 1;
  }

  const ops = [];
  for (let i = 0; i < prefix; i += 1) {
    ops.push({ type: 'equal', oldLine: i + 1, newLine: i + 1, text: beforeLines[i] });
  }
  const midOps = lcsOps(
    beforeLines.slice(prefix, aLen - suffix),
    afterLines.slice(prefix, bLen - suffix),
    prefix,
    prefix
  );
  for (let i = 0; i < midOps.length; i += 1) {
    ops.push(midOps[i]);
  }
  for (let s = 0; s < suffix; s += 1) {
    const oldIdx = aLen - suffix + s;
    const newIdx = bLen - suffix + s;
    ops.push({ type: 'equal', oldLine: oldIdx + 1, newLine: newIdx + 1, text: beforeLines[oldIdx] });
  }
  return ops;
}

/** Groups changed operations with surrounding context lines into unified hunks. */
function buildDiffHunks(beforeText, afterText, options = {}) {
  const contextLines = typeof options.contextLines === 'number' && options.contextLines >= 0
    ? options.contextLines
    : 2;
  const maxLines = typeof options.maxLines === 'number' && options.maxLines > 0
    ? options.maxLines
    : 140;

  const ops = computeLineDiff(beforeText, afterText);
  let added = 0;
  let removed = 0;
  const changeIndices = [];

  for (let idx = 0; idx < ops.length; idx += 1) {
    if (ops[idx].type === 'add') {
      added += 1;
      changeIndices.push(idx);
    } else if (ops[idx].type === 'remove') {
      removed += 1;
      changeIndices.push(idx);
    }
  }

  if (changeIndices.length === 0) {
    return {
      changed: false,
      added: 0,
      removed: 0,
      truncated: false,
      hunks: []
    };
  }

  const windows = [];
  for (let i = 0; i < changeIndices.length; i += 1) {
    const idx = changeIndices[i];
    const start = Math.max(0, idx - contextLines);
    const end = Math.min(ops.length - 1, idx + contextLines);
    const last = windows[windows.length - 1];
    if (last && start <= last.end + 1) {
      last.end = Math.max(last.end, end);
    } else {
      windows.push({ start, end });
    }
  }

  const hunks = [];
  let emitted = 0;
  let truncated = false;
  for (let w = 0; w < windows.length; w += 1) {
    const win = windows[w];
    const lines = [];
    let oldStart = 0;
    let newStart = 0;
    let oldCount = 0;
    let newCount = 0;

    for (let k = win.start; k <= win.end; k += 1) {
      if (emitted >= maxLines) {
        truncated = true;
        break;
      }
      const op = ops[k];
      if (op.type !== 'add') {
        if (oldStart === 0) { oldStart = op.oldLine; }
        oldCount += 1;
      }
      if (op.type !== 'remove') {
        if (newStart === 0) { newStart = op.newLine; }
        newCount += 1;
      }
      lines.push({
        type: op.type === 'equal' ? 'context' : op.type,
        oldLine: op.oldLine,
        newLine: op.newLine,
        text: op.text
      });
      emitted += 1;
    }

    if (lines.length > 0) {
      hunks.push({
        oldStart: oldStart || 1,
        oldCount,
        newStart: newStart || 1,
        newCount,
        lines
      });
    }
    if (truncated) {
      break;
    }
  }

  return {
    changed: added > 0 || removed > 0,
    added,
    removed,
    truncated,
    hunks
  };
}

/** Fast added/removed summary using computeLineDiff. */
function summarizeDiffStats(beforeText, afterText) {
  if (beforeText === afterText) {
    return { changed: false, added: 0, removed: 0 };
  }
  const ops = computeLineDiff(beforeText, afterText);
  let added = 0;
  let removed = 0;
  for (let i = 0; i < ops.length; i += 1) {
    if (ops[i].type === 'add') { added += 1; }
    else if (ops[i].type === 'remove') { removed += 1; }
  }
  return { changed: added > 0 || removed > 0, added, removed };
}

/** Formats a unified diff text preview for tool output back to the model. */
function formatDiffText(beforeText, afterText, maxLines = 48) {
  const built = buildDiffHunks(beforeText, afterText, { contextLines: 2, maxLines });
  if (!built.changed) {
    return '(无文本内容差异)';
  }
  const rows = [];
  for (let h = 0; h < built.hunks.length; h += 1) {
    const hunk = built.hunks[h];
    rows.push(`@@ -${hunk.oldStart},${hunk.oldCount} +${hunk.newStart},${hunk.newCount} @@`);
    for (let l = 0; l < hunk.lines.length; l += 1) {
      const line = hunk.lines[l];
      const prefix = line.type === 'add' ? '+' : line.type === 'remove' ? '-' : ' ';
      rows.push(`${prefix}${line.text}`);
    }
  }
  if (built.truncated) {
    rows.push('... (差异较长，剩余行可在差异预览卡片中展开)');
  }
  return rows.join('\n');
}

module.exports = {
  splitLines,
  computeLineDiff,
  buildDiffHunks,
  summarizeDiffStats,
  formatDiffText
};

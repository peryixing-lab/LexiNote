export class LexiMathToken {
  start: number = 0;
  end: number = 0;
  text: string = '';
  displayMode: boolean = false;
}

export class LexiMathDisplayBlock {
  text: string = '';
  endLine: number = 0;
}

const MATH_ENVIRONMENTS: string[] = [
  'equation', 'equation*',
  'align', 'align*', 'aligned',
  'alignat', 'alignat*', 'alignedat',
  'gather', 'gather*', 'gathered',
  'flalign', 'flalign*',
  'multline', 'multline*',
  'split',
  'cases', 'cases*', 'dcases', 'dcases*', 'rcases', 'rcases*', 'numcases', 'subnumcases',
  'matrix', 'pmatrix', 'bmatrix', 'Bmatrix', 'vmatrix', 'Vmatrix', 'smallmatrix',
  'array', 'subarray', 'CD',
  'eqnarray', 'eqnarray*'
];

/** Finds math without interpreting LaTeX commands or changing the source document. */
export class LexiMathSyntax {
  static isEscaped(text: string, index: number): boolean {
    let slashes = 0;
    for (let cursor = index - 1; cursor >= 0 && text[cursor] === '\\'; cursor--) { slashes++; }
    return slashes % 2 === 1;
  }

  static isMathEnvironment(name: string): boolean {
    return MATH_ENVIRONMENTS.includes(name);
  }

  private static isDisplayEnvironment(name: string): boolean {
    return name === 'equation' || name === 'equation*' ||
      name === 'align' || name === 'align*' ||
      name === 'alignat' || name === 'alignat*' ||
      name === 'gather' || name === 'gather*' ||
      name === 'flalign' || name === 'flalign*' ||
      name === 'multline' || name === 'multline*' ||
      name === 'numcases' || name === 'subnumcases' ||
      name === 'eqnarray' || name === 'eqnarray*';
  }

  private static matchEnvironmentAt(text: string, index: number): LexiMathToken | undefined {
    if (text[index] !== '\\' || text.substring(index, index + 7) !== '\\begin{') {
      return undefined;
    }
    const openMatch = /^\\begin\{([A-Za-z]+\*?)\}/.exec(text.substring(index));
    if (!openMatch) { return undefined; }
    const envName = openMatch[1];
    if (!LexiMathSyntax.isMathEnvironment(envName)) { return undefined; }
    const openTag = `\\begin{${envName}}`;
    const closeTag = `\\end{${envName}}`;
    let depth = 1;
    let cursor = index + openTag.length;
    while (cursor < text.length) {
      const nextOpen = text.indexOf(openTag, cursor);
      const nextClose = text.indexOf(closeTag, cursor);
      if (nextClose < 0) { return undefined; }
      if (nextOpen >= 0 && nextOpen < nextClose) {
        depth++;
        cursor = nextOpen + openTag.length;
      } else {
        depth--;
        cursor = nextClose + closeTag.length;
        if (depth === 0) {
          const token = new LexiMathToken();
          token.start = index;
          token.end = cursor;
          token.text = text.substring(index, cursor);
          token.displayMode = true;
          return token;
        }
      }
    }
    return undefined;
  }

  private static isValidDollarBody(rawBody: string, afterClose: string): boolean {
    const trimmed = rawBody.trim();
    if (!trimmed) { return false; }
    if (/[0-9]/.test(afterClose)) { return false; }
    // Reject currency spans such as "$5，而公式是$" or "$5 and $10" where a number is followed by prose.
    if (/^[0-9]+(?:[.,][0-9]+)*\s*(?:[\u3000-\u303f\u4e00-\u9fff\uff00-\uffef,.;:!?)—–\-]|and\b|or\b|to\b|per\b)/i.test(trimmed) &&
      !/\\[A-Za-z]|[=^_{}<>]/.test(trimmed)) {
      return false;
    }
    const hasLeadingSpace = /^\s/.test(rawBody);
    const hasTrailingSpace = /\s$/.test(rawBody);
    if (!hasLeadingSpace && !hasTrailingSpace) { return true; }
    if (!hasLeadingSpace || !hasTrailingSpace) { return false; }
    // Allow symmetric "$ ... $" with spaces when the content contains LaTeX commands or math operators.
    if (/\\[A-Za-z]|[_^=<>+\-*/{}]/.test(trimmed)) {
      return !/^[0-9]+(?:[.,][0-9]+)*\s+[A-Za-z\u4e00-\u9fff]/.test(trimmed);
    }
    return false;
  }

  static inlineTokens(text: string): LexiMathToken[] {
    const tokens: LexiMathToken[] = [];
    let index = 0;
    while (index < text.length) {
      if (LexiMathSyntax.isEscaped(text, index)) { index++; continue; }
      if (text[index] === '`') {
        let length = 1;
        while (text[index + length] === '`') { length++; }
        const marker = '`'.repeat(length);
        let closing = text.indexOf(marker, index + length);
        while (closing >= 0 && (text[closing - 1] === '`' || text[closing + length] === '`')) {
          closing = text.indexOf(marker, closing + length);
        }
        if (closing >= 0) { index = closing + length; continue; }
        index += length;
        continue;
      }
      // Targets are literal addresses; a dollar in a URL or wiki target is not math.
      if (text.substring(index, index + 2) === '[[') {
        const closing = text.indexOf(']]', index + 2);
        if (closing >= 0) { index = closing + 2; continue; }
      }
      if (text.substring(index, index + 2) === '](') {
        const closing = text.indexOf(')', index + 2);
        if (closing >= 0) { index = closing + 1; continue; }
      }
      if (text.substring(index, index + 7) === '\\begin{') {
        const envToken = LexiMathSyntax.matchEnvironmentAt(text, index);
        if (envToken) {
          tokens.push(envToken);
          index = envToken.end;
          continue;
        }
      }
      let opener = '';
      let closer = '';
      let display = false;
      const pair = text.substring(index, index + 2);
      if (pair === '\\(') { opener = pair; closer = '\\)'; }
      else if (pair === '\\[') { opener = pair; closer = '\\]'; display = true; }
      else if (pair === '$$') { opener = pair; closer = pair; display = true; }
      else if (text[index] === '$' && text[index + 1] !== '\n' && text[index + 1] !== '\r' && index + 1 < text.length) {
        opener = '$'; closer = '$';
      }
      if (!opener) { index++; continue; }
      const bodyStart = index + opener.length;
      let closing = bodyStart;
      let found = false;
      let braceDepth = 0;
      let envDepth = 0;
      while (closing < text.length) {
        const ch = text[closing];
        if (!LexiMathSyntax.isEscaped(text, closing)) {
          if (ch === '{') { braceDepth++; closing++; continue; }
          if (ch === '}' && braceDepth > 0) { braceDepth--; closing++; continue; }
          if (ch === '\\' && text.substring(closing, closing + 7) === '\\begin{') {
            envDepth++;
          } else if (ch === '\\' && text.substring(closing, closing + 5) === '\\end{' && envDepth > 0) {
            envDepth--;
          }
        }
        if (!display && (ch === '\n' || ch === '\r') && envDepth === 0) {
          break;
        }
        const canClose = closer !== '$' || (braceDepth === 0 && envDepth === 0);
        if (canClose && text.substring(closing, closing + closer.length) === closer &&
          (closer !== '$' || !LexiMathSyntax.isEscaped(text, closing))) {
          const rawBody = text.substring(bodyStart, closing);
          if (closer === '$') {
            found = LexiMathSyntax.isValidDollarBody(rawBody, text[closing + 1] || '');
          } else {
            found = rawBody.trim().length > 0;
          }
          break;
        }
        closing++;
      }
      if (found) {
        const token = new LexiMathToken();
        token.start = index;
        token.end = closing + closer.length;
        token.text = text.substring(bodyStart, closing).trim();
        if (!display && /^\\begin\{([A-Za-z]+\*?)\}/.test(token.text)) {
          const envMatch = /^\\begin\{([A-Za-z]+\*?)\}/.exec(token.text);
          if (envMatch && LexiMathSyntax.isDisplayEnvironment(envMatch[1])) {
            display = true;
          }
        }
        token.displayMode = display;
        tokens.push(token);
        index = token.end;
      } else {
        index += opener.length;
      }
    }
    return tokens;
  }

  static hasMath(text: string): boolean {
    return LexiMathSyntax.inlineTokens(text).length > 0;
  }

  static hasUnclosedMath(text: string): boolean {
    const tokens = LexiMathSyntax.inlineTokens(text);
    let masked = '';
    let cursor = 0;
    for (const token of tokens) {
      masked += text.substring(cursor, token.start);
      cursor = token.end;
    }
    masked += text.substring(cursor);
    if (/(?:^|[^\\])\$\$/.test(masked) || /\\\[/.test(masked) || /\\\(/.test(masked)) {
      return true;
    }
    const beginMatch = /\\begin\{([A-Za-z]+\*?)\}/.exec(masked);
    if (beginMatch && LexiMathSyntax.isMathEnvironment(beginMatch[1])) {
      return true;
    }
    return false;
  }

  static displayBlock(lines: string[], startLine: number): LexiMathDisplayBlock | undefined {
    const first = (lines[startLine] || '').trim();
    const envOpen = /^\\begin\{([A-Za-z]+\*?)\}/.exec(first);
    if (envOpen && LexiMathSyntax.isMathEnvironment(envOpen[1])) {
      const envName = envOpen[1];
      const openTag = `\\begin{${envName}}`;
      const closeTag = `\\end{${envName}}`;
      let depth = 0;
      const body: string[] = [];
      for (let lineIndex = startLine; lineIndex < lines.length; lineIndex++) {
        const rawLine = lines[lineIndex].replace(/\r$/, '');
        if (lineIndex > startLine && /^\s*(?:#{1,6}\s|`{3,}|~{3,})/.test(rawLine)) { return undefined; }
        body.push(rawLine);
        let cursor = 0;
        while (cursor < rawLine.length) {
          const nextOpen = rawLine.indexOf(openTag, cursor);
          const nextClose = rawLine.indexOf(closeTag, cursor);
          if (nextOpen < 0 && nextClose < 0) { break; }
          if (nextOpen >= 0 && (nextClose < 0 || nextOpen < nextClose)) {
            depth++;
            cursor = nextOpen + openTag.length;
          } else {
            depth--;
            cursor = nextClose + closeTag.length;
            if (depth === 0) {
              const trailing = rawLine.substring(cursor).trim();
              if (trailing.length > 0 && !/^(\\tag\*?\{[^}]*\}|%.*)*$/.test(trailing)) {
                return undefined;
              }
              const result = new LexiMathDisplayBlock();
              result.text = body.join('\n').trim();
              result.endLine = lineIndex;
              return result;
            }
          }
        }
      }
      return undefined;
    }
    const opener = first.startsWith('$$') ? '$$' : first.startsWith('\\[') ? '\\[' : '';
    if (!opener) { return undefined; }
    const closer = opener === '$$' ? '$$' : '\\]';
    const body: string[] = [];
    for (let lineIndex = startLine; lineIndex < lines.length; lineIndex++) {
      const line = lineIndex === startLine ? first.substring(opener.length) : lines[lineIndex].replace(/\r$/, '');
      let search = 0;
      let closing = line.indexOf(closer, search);
      while (closing >= 0 && LexiMathSyntax.isEscaped(line, closing)) {
        search = closing + closer.length;
        closing = line.indexOf(closer, search);
      }
      if (closing >= 0) {
        const trailing = line.substring(closing + closer.length).trim();
        if (trailing.length > 0 && !trailing.startsWith('%')) { return undefined; }
        body.push(line.substring(0, closing));
        const result = new LexiMathDisplayBlock();
        result.text = body.join('\n').trim();
        result.endLine = lineIndex;
        return result;
      }
      // A later Markdown block is not part of an unfinished formula.
      if (lineIndex > startLine && /^\s*(?:#{1,6}\s|`{3,}|~{3,})/.test(line)) { return undefined; }
      body.push(line);
    }
    return undefined;
  }
}

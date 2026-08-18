/**
 * Helpers（ArkTS 适配版：显式类型、无索引签名/any/unknown、字符串用 charAt）
 */
const escapeTest = /[&<>"']/;
const escapeReplace = new RegExp(escapeTest.source, 'g');
const escapeTestNoEncode = /[<>"']|&(?!(#\d{1,7}|#[Xx][a-fA-F0-9]{1,6}|\w+);)/;
const escapeReplaceNoEncode = new RegExp(escapeTestNoEncode.source, 'g');
const escapeReplacements: Map<string, string> = new Map<string, string>([
  ['&', '&amp;'],
  ['<', '&lt;'],
  ['>', '&gt;'],
  ['"', '&quot;'],
  ["'", '&#39;']
]);
const getEscapeReplacement = (ch: string): string => escapeReplacements.get(ch) ?? ch;

export function escape(html: string, encode?: boolean): string {
  if (encode) {
    if (escapeTest.test(html)) {
      return html.replace(escapeReplace, getEscapeReplacement);
    }
  } else {
    if (escapeTestNoEncode.test(html)) {
      return html.replace(escapeReplaceNoEncode, getEscapeReplacement);
    }
  }

  return html;
}

const unescapeTest = /&(#(?:\d+)|(?:#x[0-9A-Fa-f]+)|(?:\w+));?/ig;

export function unescape(html: string): string {
  // explicitly match decimal, hex, and named HTML entities
  return html.replace(unescapeTest, (match: string, captured: string): string => {
    let n = captured.toLowerCase();
    if (n === 'colon') return ':';
    if (n.charAt(0) === '#') {
      return n.charAt(1) === 'x'
        ? String.fromCharCode(parseInt(n.substring(2), 16))
        : String.fromCharCode(parseInt(n.substring(1), 10));
    }
    return '';
  });
}

const caret = /(^|[^\[])\^/g;

/** 可编辑正则构造器（ArkTS class 实现，替代对象字面量自引用） */
class RegexEditor {
  private source: string;
  private options: string;

  constructor(regex: string | RegExp, opt?: string) {
    this.source = typeof regex === 'string' ? regex : regex.source;
    this.options = opt || '';
  }

  replace(name: string | RegExp, val: string | RegExp): RegexEditor {
    let valSource = typeof val === 'string' ? val : val.source;
    valSource = valSource.replace(caret, '$1');
    this.source = this.source.replace(name, valSource);
    return this;
  }

  getRegex(): RegExp {
    return new RegExp(this.source, this.options);
  }
}

export function edit(regex: string | RegExp, opt?: string): RegexEditor {
  return new RegexEditor(regex, opt);
}

export function cleanUrl(href: string): string | null {
  try {
    href = encodeURI(href).replace(/%25/g, '%');
  } catch (e) {
    return null;
  }
  return href;
}

/** 永不匹配的 RegExp 兜底（替代 noopTest） */
export const noopTest = /(?!)/;

export function splitCells(tableRow: string, count?: number): string[] {
  // ensure that every cell-delimiting pipe has a space
  // before it to distinguish it from an escaped pipe
  const row = tableRow.replace(/\|/g, (match: string, offset: number, str: string): string => {
      let escaped = false;
      let curr = offset;
      while (--curr >= 0 && str.charAt(curr) === '\\') escaped = !escaped;
      if (escaped) {
        // odd number of slashes means | is escaped
        // so we leave it alone
        return '|';
      } else {
        // add space before unescaped |
        return ' |';
      }
    });
  const cells: string[] = row.split(/ \|/);
  let i = 0;

  // First/last cell in a row cannot be empty if it has no leading/trailing pipe
  if (!cells[0].trim()) {
    cells.shift();
  }
  if (cells.length > 0 && !cells[cells.length - 1].trim()) {
    cells.pop();
  }

  if (count) {
    if (cells.length > count) {
      cells.splice(count);
    } else {
      while (cells.length < count) cells.push('');
    }
  }

  for (; i < cells.length; i++) {
    // leading or trailing whitespace is ignored per the gfm spec
    cells[i] = cells[i].trim().replace(/\\\|/g, '|');
  }
  return cells;
}

/**
 * Remove trailing 'c's. Equivalent to str.replace(/c*$/, '').
 * /c*$/ is vulnerable to REDOS.
 *
 * @param str
 * @param c
 * @param invert Remove suffix of non-c chars instead. Default falsey.
 */
export function rtrim(str: string, c: string, invert?: boolean): string {
  const l = str.length;
  if (l === 0) {
    return '';
  }

  // Length of suffix matching the invert condition.
  let suffLen = 0;

  // Step left until we fail to match the invert condition.
  while (suffLen < l) {
    const currChar = str.charAt(l - suffLen - 1);
    if (currChar === c && !invert) {
      suffLen++;
    } else if (currChar !== c && invert) {
      suffLen++;
    } else {
      break;
    }
  }

  return str.slice(0, l - suffLen);
}

export function findClosingBracket(str: string, b: string): number {
  if (str.indexOf(b.charAt(1)) === -1) {
    return -1;
  }

  let level = 0;
  for (let i = 0; i < str.length; i++) {
    if (str.charAt(i) === '\\') {
      i++;
    } else if (str.charAt(i) === b.charAt(0)) {
      level++;
    } else if (str.charAt(i) === b.charAt(1)) {
      level--;
      if (level < 0) {
        return i;
      }
    }
  }
  return -1;
}

import { _defaults } from './defaults';
import {
  cleanUrl,
  escape
} from './helpers';
import type { MarkedOptions } from './MarkedOptions';
import type { Tokens } from './Tokens';
import type { _Parser } from './Parser';

/**
 * Renderer（ArkTS 适配版：参数不用解构，改为字段访问）
 */
export class _Renderer {
  options: MarkedOptions;
  parser!: _Parser; // set by the parser
  constructor(options?: MarkedOptions) {
    this.options = options || _defaults;
  }

  space(token: Tokens.Space): string {
    return '';
  }

  code(token: Tokens.Code): string {
    const langString = (token.lang || '').match(/^\S*/)?.[0];

    const code = token.text.replace(/\n$/, '') + '\n';

    if (!langString) {
      return '<pre><code>'
        + (token.escaped ? code : escape(code, true))
        + '</code></pre>\n';
    }

    return '<pre><code class="language-'
      + escape(langString)
      + '">'
      + (token.escaped ? code : escape(code, true))
      + '</code></pre>\n';
  }

  blockquote(token: Tokens.Blockquote): string {
    const body = this.parser.parse(token.tokens);
    return `<blockquote>\n${body}</blockquote>\n`;
  }

  html(token: Tokens.HTML | Tokens.Tag): string {
    return token.text;
  }

  heading(token: Tokens.Heading): string {
    return `<h${token.depth}>${this.parser.parseInline(token.tokens)}</h${token.depth}>\n`;
  }

  hr(token: Tokens.Hr): string {
    return '<hr>\n';
  }

  list(token: Tokens.List): string {
    const ordered = token.ordered;
    const start = token.start;

    let body = '';
    for (let j = 0; j < token.items.length; j++) {
      const item = token.items[j];
      body += this.listitem(item);
    }

    const type = ordered ? 'ol' : 'ul';
    const startAttr = (ordered && start !== 1) ? (' start="' + start + '"') : '';
    return '<' + type + startAttr + '>\n' + body + '</' + type + '>\n';
  }

  listitem(item: Tokens.ListItem): string {
    let itemBody = '';
    if (item.task) {
      const checkbox = this.checkbox({ checked: !!item.checked });
      if (item.loose) {
        if (item.tokens.length > 0 && item.tokens[0].type === 'paragraph') {
          const para = item.tokens[0] as Tokens.Paragraph;
          para.text = checkbox + ' ' + para.text;
          if (para.tokens && para.tokens.length > 0 && para.tokens[0].type === 'text') {
            const firstText = para.tokens[0] as Tokens.Text;
            firstText.text = checkbox + ' ' + firstText.text;
          }
        } else {
          item.tokens.unshift({
            type: 'text',
            raw: checkbox + ' ',
            text: checkbox + ' '
          } as Tokens.Text);
        }
      } else {
        itemBody += checkbox + ' ';
      }
    }

    itemBody += this.parser.parse(item.tokens, !!item.loose);

    return `<li>${itemBody}</li>\n`;
  }

  checkbox(token: Tokens.Checkbox): string {
    return '<input '
      + (token.checked ? 'checked="" ' : '')
      + 'disabled="" type="checkbox">';
  }

  paragraph(token: Tokens.Paragraph): string {
    return `<p>${this.parser.parseInline(token.tokens)}</p>\n`;
  }

  table(token: Tokens.Table): string {
    let header = '';

    // header
    let cell = '';
    for (let j = 0; j < token.header.length; j++) {
      cell += this.tablecell(token.header[j]);
    }
    header += this.tablerow({ text: cell });

    let body = '';
    for (let j = 0; j < token.rows.length; j++) {
      const row = token.rows[j];

      cell = '';
      for (let k = 0; k < row.length; k++) {
        cell += this.tablecell(row[k]);
      }

      body += this.tablerow({ text: cell });
    }
    if (body) body = `<tbody>${body}</tbody>`;

    return '<table>\n'
      + '<thead>\n'
      + header
      + '</thead>\n'
      + body
      + '</table>\n';
  }

  tablerow(token: Tokens.TableRow): string {
    return `<tr>\n${token.text}</tr>\n`;
  }

  tablecell(token: Tokens.TableCell): string {
    const content = this.parser.parseInline(token.tokens);
    const type = token.header ? 'th' : 'td';
    const tag = token.align
      ? `<${type} align="${token.align}">`
      : `<${type}>`;
    return tag + content + `</${type}>\n`;
  }

  /**
   * span level renderer
   */
  strong(token: Tokens.Strong): string {
    return `<strong>${this.parser.parseInline(token.tokens)}</strong>`;
  }

  em(token: Tokens.Em): string {
    return `<em>${this.parser.parseInline(token.tokens)}</em>`;
  }

  codespan(token: Tokens.Codespan): string {
    return `<code>${token.text}</code>`;
  }

  br(token: Tokens.Br): string {
    return '<br>';
  }

  del(token: Tokens.Del): string {
    return `<del>${this.parser.parseInline(token.tokens)}</del>`;
  }

  link(token: Tokens.Link): string {
    const text = this.parser.parseInline(token.tokens);
    let cleanHref = cleanUrl(token.href);
    if (cleanHref === null) {
      return text;
    }
    let out = '<a href="' + cleanHref + '"';
    if (token.title) {
      out += ' title="' + token.title + '"';
    }
    out += '>' + text + '</a>';
    return out;
  }

  image(token: Tokens.Image): string {
    const cleanHref = cleanUrl(token.href);
    if (cleanHref === null) {
      return token.text;
    }

    let out = `<img src="${cleanHref}" alt="${token.text}"`;
    if (token.title) {
      out += ` title="${token.title}"`;
    }
    out += '>';
    return out;
  }

  text(token: Tokens.Text | Tokens.Escape | Tokens.Tag): string {
    // 支持带 tokens 的 text（内联子 token），否则输出纯文本
    const textToken = token as Tokens.Text;
    return textToken.tokens && textToken.tokens.length > 0 ? this.parser.parseInline(textToken.tokens) : token.text;
  }
}

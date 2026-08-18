import { _Tokenizer } from './Tokenizer';
import { _defaults } from './defaults';
import { block, inline, Rules } from './rules';
import { TokensList, LinkRef } from './Tokens';
import type { Token, Tokens } from './Tokens';
import type { MarkedOptions } from './MarkedOptions';

/** 词法分析状态 */
interface LexerState {
  inLink: boolean;
  inRawBlock: boolean;
  top: boolean;
}

/** 待处理的行内队列项 */
interface InlineQueueItem {
  src: string;
  tokens: Token[];
}

/**
 * Block Lexer（ArkTS 适配版：不依赖扩展 tokenizer/startIndex，links 用 Map）
 */
export class _Lexer {
  tokens: TokensList;
  options: MarkedOptions;
  state: LexerState;

  private tokenizer: _Tokenizer;
  private inlineQueue: InlineQueueItem[];

  constructor(options?: MarkedOptions) {
    // TokenList cannot be created in one go
    this.tokens = new TokensList();
    this.tokens.links = new Map();
    this.options = options || _defaults;
    this.options.tokenizer = this.options.tokenizer || new _Tokenizer();
    this.tokenizer = this.options.tokenizer;
    this.tokenizer.options = this.options;
    this.tokenizer.lexer = this;
    this.inlineQueue = [];
    this.state = {
      inLink: false,
      inRawBlock: false,
      top: true
    };

    const rules: Rules = {
      block: block.normal,
      inline: inline.normal
    };

    if (this.options.pedantic) {
      rules.block = block.pedantic;
      rules.inline = inline.pedantic;
    } else if (this.options.gfm) {
      rules.block = block.gfm;
      if (this.options.breaks) {
        rules.inline = inline.breaks;
      } else {
        rules.inline = inline.gfm;
      }
    }
    this.tokenizer.rules = rules;
  }

  /**
   * Static Lex Method
   */
  static lex(src: string, options?: MarkedOptions): TokensList {
    const lexer = new _Lexer(options);
    return lexer.lex(src);
  }

  /**
   * Static Lex Inline Method
   */
  static lexInline(src: string, options?: MarkedOptions): Token[] {
    const lexer = new _Lexer(options);
    return lexer.inlineTokens(src);
  }

  /**
   * Preprocessing
   */
  lex(src: string): TokensList {
    src = src
      .replace(/\r\n|\r/g, '\n');

    this.blockTokens(src, this.tokens);

    for (let i = 0; i < this.inlineQueue.length; i++) {
      const next = this.inlineQueue[i];
      this.inlineTokens(next.src, next.tokens);
    }
    this.inlineQueue = [];

    return this.tokens;
  }

  /**
   * Lexing
   */
  blockTokens(src: string, tokens: Token[] = [], lastParagraphClipped: boolean = false): Token[] {
    if (this.options.pedantic) {
      src = src.replace(/\t/g, '    ').replace(/^ +$/gm, '');
    } else {
      src = src.replace(/^( *)(\t+)/gm, (match: string, leading: string, tabs: string): string => {
        return leading + '    '.repeat(tabs.length);
      });
    }

    let token: Tokens.Generic | undefined;
    let lastToken: Token | undefined;

    while (src) {
      // newline
      token = this.tokenizer.space(src) as Tokens.Generic;
      if (token) {
        src = src.substring(token.raw.length);
        if (token.raw.length === 1 && tokens.length > 0) {
          // if there's a single \n as a spacer, it's terminating the last line,
          // so move it there so that we don't get unnecessary paragraph tags
          const last = tokens[tokens.length - 1];
          last.raw += '\n';
        } else {
          tokens.push(token);
        }
        continue;
      }

      // code
      token = this.tokenizer.code(src) as Tokens.Generic;
      if (token) {
        src = src.substring(token.raw.length);
        lastToken = tokens[tokens.length - 1];
        // An indented code block cannot interrupt a paragraph.
        if (lastToken && (lastToken.type === 'paragraph' || lastToken.type === 'text')) {
          lastToken.raw += '\n' + token.raw;
          (lastToken as Tokens.Text).text += '\n' + token.text;
          this.inlineQueue[this.inlineQueue.length - 1].src = (lastToken as Tokens.Text).text;
        } else {
          tokens.push(token);
        }
        continue;
      }

      // fences
      token = this.tokenizer.fences(src) as Tokens.Generic;
      if (token) {
        src = src.substring(token.raw.length);
        tokens.push(token);
        continue;
      }

      // heading
      token = this.tokenizer.heading(src) as Tokens.Generic;
      if (token) {
        src = src.substring(token.raw.length);
        tokens.push(token);
        continue;
      }

      // hr
      token = this.tokenizer.hr(src) as Tokens.Generic;
      if (token) {
        src = src.substring(token.raw.length);
        tokens.push(token);
        continue;
      }

      // blockquote
      token = this.tokenizer.blockquote(src) as Tokens.Generic;
      if (token) {
        src = src.substring(token.raw.length);
        tokens.push(token);
        continue;
      }

      // list
      token = this.tokenizer.list(src) as Tokens.Generic;
      if (token) {
        src = src.substring(token.raw.length);
        tokens.push(token);
        continue;
      }

      // html
      token = this.tokenizer.html(src) as Tokens.Generic;
      if (token) {
        src = src.substring(token.raw.length);
        tokens.push(token);
        continue;
      }

      // def
      token = this.tokenizer.def(src) as Tokens.Generic;
      if (token) {
        const defToken = token as Tokens.Def;
        src = src.substring(defToken.raw.length);
        lastToken = tokens[tokens.length - 1];
        if (lastToken && (lastToken.type === 'paragraph' || lastToken.type === 'text')) {
          lastToken.raw += '\n' + defToken.raw;
          (lastToken as Tokens.Text).text += '\n' + defToken.raw;
          this.inlineQueue[this.inlineQueue.length - 1].src = (lastToken as Tokens.Text).text;
        } else if (!this.tokens.links.has(defToken.tag)) {
          this.tokens.links.set(defToken.tag, {
            href: defToken.href,
            title: defToken.title
          });
        }
        continue;
      }

      // table (gfm)
      token = this.tokenizer.table(src) as Tokens.Generic;
      if (token) {
        src = src.substring(token.raw.length);
        tokens.push(token);
        continue;
      }

      // lheading
      token = this.tokenizer.lheading(src) as Tokens.Generic;
      if (token) {
        src = src.substring(token.raw.length);
        tokens.push(token);
        continue;
      }

      // top-level paragraph
      if (this.state.top) {
        token = this.tokenizer.paragraph(src) as Tokens.Generic;
        if (token) {
          lastToken = tokens[tokens.length - 1];
          if (lastParagraphClipped && lastToken && lastToken.type === 'paragraph') {
            lastToken.raw += '\n' + token.raw;
            (lastToken as Tokens.Text).text += '\n' + token.text;
            this.inlineQueue.pop();
            this.inlineQueue[this.inlineQueue.length - 1].src = (lastToken as Tokens.Text).text;
          } else {
            tokens.push(token);
          }
          lastParagraphClipped = false; // 无扩展 startBlock 场景，段落不会被裁剪
          src = src.substring(token.raw.length);
          continue;
        }
      }

      // text
      token = this.tokenizer.text(src) as Tokens.Generic;
      if (token) {
        src = src.substring(token.raw.length);
        lastToken = tokens[tokens.length - 1];
        if (lastToken && lastToken.type === 'text') {
          lastToken.raw += '\n' + token.raw;
          (lastToken as Tokens.Text).text += '\n' + token.text;
          this.inlineQueue.pop();
          this.inlineQueue[this.inlineQueue.length - 1].src = (lastToken as Tokens.Text).text;
        } else {
          tokens.push(token);
        }
        continue;
      }

      if (src) {
        const errMsg = 'Infinite loop on byte: ' + src.charCodeAt(0);
        if (this.options.silent) {
          console.error(errMsg);
          break;
        } else {
          throw new Error(errMsg);
        }
      }
    }

    this.state.top = true;
    return tokens;
  }

  inline(src: string, tokens: Token[] = []): Token[] {
    this.inlineQueue.push({ src, tokens });
    return tokens;
  }

  /**
   * Lexing/Compiling
   */
  inlineTokens(src: string, tokens: Token[] = []): Token[] {
    let token: Tokens.Generic | undefined;
    let lastToken: Token | undefined;
    let cutSrc: string;

    // String with links masked to avoid interference with em and strong
    let maskedSrc = src;
    let match: RegExpExecArray | null;
    let keepPrevChar: boolean = false;
    let prevChar: string = '';

    // Mask out reflinks
    if (this.tokens.links.size > 0) {
      const links: string[] = [];
      this.tokens.links.forEach((value: LinkRef, key: string) => {
        links.push(key);
      });
      if (links.length > 0) {
        const reflinkSearch = this.tokenizer.rules.inline.reflinkSearch;
        reflinkSearch.lastIndex = 0;
        while ((match = reflinkSearch.exec(maskedSrc)) != null) {
          if (links.includes(match[0].slice(match[0].lastIndexOf('[') + 1, -1))) {
            maskedSrc = maskedSrc.slice(0, match.index) + '[' + 'a'.repeat(match[0].length - 2) + ']' + maskedSrc.slice(reflinkSearch.lastIndex);
          }
        }
      }
    }
    // Mask out other blocks
    const blockSkip = this.tokenizer.rules.inline.blockSkip;
    blockSkip.lastIndex = 0;
    while ((match = blockSkip.exec(maskedSrc)) != null) {
      maskedSrc = maskedSrc.slice(0, match.index) + '[' + 'a'.repeat(match[0].length - 2) + ']' + maskedSrc.slice(blockSkip.lastIndex);
    }

    // Mask out escaped characters
    const anyPunctuation = this.tokenizer.rules.inline.anyPunctuation;
    anyPunctuation.lastIndex = 0;
    while ((match = anyPunctuation.exec(maskedSrc)) != null) {
      maskedSrc = maskedSrc.slice(0, match.index) + '++' + maskedSrc.slice(anyPunctuation.lastIndex);
    }

    while (src) {
      if (!keepPrevChar) {
        prevChar = '';
      }
      keepPrevChar = false;

      // escape
      token = this.tokenizer.escape(src) as Tokens.Generic;
      if (token) {
        src = src.substring(token.raw.length);
        tokens.push(token);
        continue;
      }

      // tag
      token = this.tokenizer.tag(src) as Tokens.Generic;
      if (token) {
        src = src.substring(token.raw.length);
        lastToken = tokens[tokens.length - 1];
        if (lastToken && token.type === 'text' && lastToken.type === 'text') {
          lastToken.raw += token.raw;
          (lastToken as Tokens.Text).text += token.text;
        } else {
          tokens.push(token);
        }
        continue;
      }

      // link
      token = this.tokenizer.link(src) as Tokens.Generic;
      if (token) {
        src = src.substring(token.raw.length);
        tokens.push(token);
        continue;
      }

      // reflink, nolink
      token = this.tokenizer.reflink(src, this.tokens.links) as Tokens.Generic;
      if (token) {
        src = src.substring(token.raw.length);
        lastToken = tokens[tokens.length - 1];
        if (lastToken && token.type === 'text' && lastToken.type === 'text') {
          lastToken.raw += token.raw;
          (lastToken as Tokens.Text).text += token.text;
        } else {
          tokens.push(token);
        }
        continue;
      }

      // em & strong
      token = this.tokenizer.emStrong(src, maskedSrc, prevChar) as Tokens.Generic;
      if (token) {
        src = src.substring(token.raw.length);
        tokens.push(token);
        continue;
      }

      // code
      token = this.tokenizer.codespan(src) as Tokens.Generic;
      if (token) {
        src = src.substring(token.raw.length);
        tokens.push(token);
        continue;
      }

      // br
      token = this.tokenizer.br(src) as Tokens.Generic;
      if (token) {
        src = src.substring(token.raw.length);
        tokens.push(token);
        continue;
      }

      // del (gfm)
      token = this.tokenizer.del(src) as Tokens.Generic;
      if (token) {
        src = src.substring(token.raw.length);
        tokens.push(token);
        continue;
      }

      // autolink
      token = this.tokenizer.autolink(src) as Tokens.Generic;
      if (token) {
        src = src.substring(token.raw.length);
        tokens.push(token);
        continue;
      }

      // url (gfm)
      if (!this.state.inLink) {
        token = this.tokenizer.url(src) as Tokens.Generic;
        if (token) {
          src = src.substring(token.raw.length);
          tokens.push(token);
          continue;
        }
      }

      // text
      cutSrc = src;
      token = this.tokenizer.inlineText(cutSrc) as Tokens.Generic;
      if (token) {
        src = src.substring(token.raw.length);
        if (token.raw.slice(-1) !== '_') { // Track prevChar before string of ____ started
          prevChar = token.raw.slice(-1);
        }
        keepPrevChar = true;
        lastToken = tokens[tokens.length - 1];
        if (lastToken && lastToken.type === 'text') {
          lastToken.raw += token.raw;
          (lastToken as Tokens.Text).text += token.text;
        } else {
          tokens.push(token);
        }
        continue;
      }

      if (src) {
        const errMsg = 'Infinite loop on byte: ' + src.charCodeAt(0);
        if (this.options.silent) {
          console.error(errMsg);
          break;
        } else {
          throw new Error(errMsg);
        }
      }
    }

    return tokens;
  }
}

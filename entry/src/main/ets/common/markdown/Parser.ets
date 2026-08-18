import { _Renderer } from './Renderer';
import { _TextRenderer } from './TextRenderer';
import { _defaults } from './defaults';
import type { MarkedToken, Token, Tokens } from './Tokens';
import type { MarkedOptions } from './MarkedOptions';

/**
 * Parsing & Compiling（ArkTS 适配版：不依赖自定义 renderer extensions，走内置 renderer 分发）
 */
export class _Parser {
  options: MarkedOptions;
  renderer: _Renderer;
  textRenderer: _TextRenderer;
  constructor(options?: MarkedOptions) {
    this.options = options || _defaults;
    this.options.renderer = this.options.renderer || new _Renderer();
    this.renderer = this.options.renderer;
    this.renderer.options = this.options;
    this.renderer.parser = this;
    this.textRenderer = new _TextRenderer();
  }

  /**
   * Static Parse Method
   */
  static parse(tokens: Token[], options?: MarkedOptions): string {
    const parser = new _Parser(options);
    return parser.parse(tokens);
  }

  /**
   * Static Parse Inline Method
   */
  static parseInline(tokens: Token[], options?: MarkedOptions): string {
    const parser = new _Parser(options);
    return parser.parseInline(tokens);
  }

  /**
   * Parse Loop
   */
  parse(tokens: Token[], top: boolean = true): string {
    let out = '';

    for (let i = 0; i < tokens.length; i++) {
      const anyToken = tokens[i];
      const token = anyToken as MarkedToken;

      switch (token.type) {
        case 'space': {
          out += this.renderer.space(token);
          continue;
        }
        case 'hr': {
          out += this.renderer.hr(token);
          continue;
        }
        case 'heading': {
          out += this.renderer.heading(token);
          continue;
        }
        case 'code': {
          out += this.renderer.code(token);
          continue;
        }
        case 'table': {
          out += this.renderer.table(token);
          continue;
        }
        case 'blockquote': {
          out += this.renderer.blockquote(token);
          continue;
        }
        case 'list': {
          out += this.renderer.list(token);
          continue;
        }
        case 'html': {
          out += this.renderer.html(token);
          continue;
        }
        case 'paragraph': {
          out += this.renderer.paragraph(token);
          continue;
        }
        case 'text': {
          let textToken = token as Tokens.Text;
          let body = this.renderer.text(textToken);
          while (i + 1 < tokens.length && tokens[i + 1].type === 'text') {
            textToken = tokens[++i] as Tokens.Text;
            body += '\n' + this.renderer.text(textToken);
          }
          if (top) {
            out += this.renderer.paragraph({
              type: 'paragraph',
              raw: body,
              text: body,
              tokens: [{ type: 'text', raw: body, text: body }]
            } as Tokens.Paragraph);
          } else {
            out += body;
          }
          continue;
        }

        default: {
          const errMsg = 'Token with "' + token.type + '" type was not found.';
          if (this.options.silent) {
            console.error(errMsg);
            return '';
          } else {
            throw new Error(errMsg);
          }
        }
      }
    }

    return out;
  }

  /**
   * Parse Inline Tokens
   */
  parseInline(tokens: Token[], renderer?: _Renderer | _TextRenderer): string {
    const activeRenderer = renderer || this.renderer;
    let out = '';

    for (let i = 0; i < tokens.length; i++) {
      const token = tokens[i] as MarkedToken;

      switch (token.type) {
        case 'escape': {
          out += activeRenderer.text(token);
          break;
        }
        case 'html': {
          out += activeRenderer.html(token);
          break;
        }
        case 'link': {
          out += activeRenderer.link(token);
          break;
        }
        case 'image': {
          out += activeRenderer.image(token);
          break;
        }
        case 'strong': {
          out += activeRenderer.strong(token);
          break;
        }
        case 'em': {
          out += activeRenderer.em(token);
          break;
        }
        case 'codespan': {
          out += activeRenderer.codespan(token);
          break;
        }
        case 'br': {
          out += activeRenderer.br(token);
          break;
        }
        case 'del': {
          out += activeRenderer.del(token);
          break;
        }
        case 'text': {
          out += activeRenderer.text(token);
          break;
        }
        default: {
          const errMsg = 'Token with "' + token.type + '" type was not found.';
          if (this.options.silent) {
            console.error(errMsg);
            return '';
          } else {
            throw new Error(errMsg);
          }
        }
      }
    }
    return out;
  }
}

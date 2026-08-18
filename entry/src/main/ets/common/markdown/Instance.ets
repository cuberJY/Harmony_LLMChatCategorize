import { _getDefaults } from './defaults';
import { _Lexer } from './Lexer';
import { _Parser } from './Parser';
import { _Hooks } from './Hooks';
import { _Renderer } from './Renderer';
import { _Tokenizer } from './Tokenizer';
import { _TextRenderer } from './TextRenderer';
import { escape } from './helpers';
import type { MarkedExtension, MarkedOptions } from './MarkedOptions';
import type { Token, TokensList } from './Tokens';

export type MaybePromise = void | Promise<void>;

/**
 * Marked 实例（ArkTS 精简版）
 * 仅保留：构造合并选项 + parse / parseInline。
 * 移除扩展/私有方法/walkTokens 全链路（本项目仅用基础 GFM 解析 + 自定义 renderer 高亮）
 */
export class Marked {
  defaults: MarkedOptions = _getDefaults();

  /** parse 入口（与官方 marked.parse 语义一致） */
  parse: (src: string, options?: MarkedOptions) => string = (src: string, options?: MarkedOptions): string => {
    return this.mergeOptionsAndParse(src, options);
  };

  /** 行内解析入口 */
  parseInline: (src: string, options?: MarkedOptions) => string = (src: string, options?: MarkedOptions): string => {
    const opt = this.mergeOptions(options);
    const tokens = _Lexer.lexInline(src, opt);
    return _Parser.parseInline(tokens, opt);
  };

  constructor(...args: MarkedExtension[]) {
    this.use(...args);
  }

  /** 合并扩展选项到 defaults（支持 renderer/tokenizer 实例覆写） */
  use(...args: MarkedExtension[]): Marked {
    for (const pack of args) {
      const opts: MarkedOptions = this.mergeExtension(this.defaults, pack);
      // renderer 未提供时按需创建（Parser 会兜底创建，此处保持实例一致）
      if (opts.renderer === undefined || opts.renderer === null) {
        opts.renderer = new _Renderer(opts);
      }
      if (opts.tokenizer === undefined || opts.tokenizer === null) {
        opts.tokenizer = new _Tokenizer(opts);
      }
      this.defaults = opts;
    }
    return this;
  }

  setOptions(opt: MarkedOptions): Marked {
    this.defaults = this.mergeExtension(this.defaults, opt);
    return this;
  }

  /** 手写合并两个选项对象（ArkTS 不支持对象 spread） */
  private mergeExtension(base: MarkedOptions, ext: MarkedExtension): MarkedOptions {
    const merged: MarkedOptions = {
      async: ext.async !== undefined ? ext.async : base.async,
      breaks: ext.breaks !== undefined ? ext.breaks : base.breaks,
      gfm: ext.gfm !== undefined ? ext.gfm : base.gfm,
      hooks: ext.hooks !== undefined ? ext.hooks : base.hooks,
      pedantic: ext.pedantic !== undefined ? ext.pedantic : base.pedantic,
      renderer: ext.renderer !== undefined ? ext.renderer : base.renderer,
      silent: ext.silent !== undefined ? ext.silent : base.silent,
      tokenizer: ext.tokenizer !== undefined ? ext.tokenizer : base.tokenizer,
      walkTokens: ext.walkTokens !== undefined ? ext.walkTokens : base.walkTokens,
    };
    return merged;
  }

  /** 合并调用期 options（默认用 defaults） */
  private mergeOptions(options?: MarkedOptions): MarkedOptions {
    if (!options) {
      return this.defaults;
    }
    return this.mergeExtension(this.defaults, options);
  }

  /** 同步解析 Markdown → HTML（本项目只用同步路径） */
  private mergeOptionsAndParse(src: string, options?: MarkedOptions): string {
    const opt = this.mergeOptions(options);

    if (opt.hooks) {
      opt.hooks.options = opt;
    }

    let input = src;
    try {
      if (opt.hooks) {
        input = opt.hooks.preprocess(src) as string;
      }
      const tokens = _Lexer.lex(input, opt);
      let html = _Parser.parse(tokens, opt);
      if (opt.hooks) {
        html = opt.hooks.postprocess(html) as string;
      }
      return html;
    } catch (e) {
      const err = e as Error;
      if (opt.silent) {
        const msg = '<p>An error occurred:</p><pre>'
          + escape(err.message + '', true)
          + '</pre>';
        return msg;
      }
      throw err;
    }
  }
}

import type { Token } from './Tokens';
import type { _Parser } from './Parser';
import type { _Lexer } from './Lexer';
import type { _Renderer } from './Renderer';
import type { _Tokenizer } from './Tokenizer';
import type { _Hooks } from './Hooks';

/**
 * Marked 选项（ArkTS 精简版：仅保留本项目实际用到的字段，
 * 移除工具类型/索引签名/扩展体系，renderer/tokenizer 用类实例）
 */
export interface MarkedExtension {
  /** True will tell marked to await any walkTokens functions before parsing */
  async?: boolean;

  /** Enable GFM line breaks. This option requires the gfm option to be true. */
  breaks?: boolean | undefined;

  /** Enable GitHub flavored markdown. */
  gfm?: boolean | undefined;

  /** Custom hooks (preprocess / processAllTokens / postprocess) */
  hooks?: _Hooks | undefined | null;

  /** Conform to obscure parts of markdown.pl */
  pedantic?: boolean | undefined;

  /** Renderer instance（可覆写为自定义 renderer） */
  renderer?: _Renderer | undefined | null;

  /** Shows an HTML error message when rendering fails. */
  silent?: boolean | undefined;

  /** Tokenizer instance */
  tokenizer?: _Tokenizer | undefined | null;

  /** The walkTokens function gets called with every token. */
  walkTokens?: ((token: Token) => void | Promise<void>) | undefined | null;
}

/** 运行时使用的完整选项（与 MarkedExtension 一致，本实现未做额外扩展） */
export interface MarkedOptions extends MarkedExtension {
  hooks?: _Hooks | undefined | null;
  renderer?: _Renderer | undefined | null;
  tokenizer?: _Tokenizer | undefined | null;
  walkTokens?: ((token: Token) => void | Promise<void>) | undefined | null;
}

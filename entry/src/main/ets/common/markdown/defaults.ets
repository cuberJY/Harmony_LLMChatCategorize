/**
 * common/markdown 目录说明
 *
 * 本目录为 marked 的 ArkTS 移植解析核心，引入自：
 *   https://github.com/electronicminer/Harmony-Markdown-Editor （MIT 协议）
 * 原仓库 Markdown/src/main/ets/core/ 目录即 marked（https://github.com/markedjs/marked）
 * 的 ArkTS 移植版，提供完整的 GFM（GitHub Flavored Markdown）解析能力。
 *
 * 本工程提取其「纯解析层」（Lexer / Parser / Tokenizer / Renderer / TextRenderer /
 * Hooks / rules / helpers / defaults / Tokens / MarkedOptions / Instance），并做了
 * ArkTS 严格模式（arkts-no-*）兼容改造：
 *  - 移除自定义扩展机制（renderer/tokenizer extensions，本项目未使用）
 *  - any/unknown、索引签名、工具类型、交叉类型、对象字面量类型 → 显式类型 / Map / class
 *  - 解构参数/声明、数组展开、Function.call/apply、in 操作符 → 字段访问 / Array.from / 去扩展
 *  - 所有 tokenizer 返回赋值加显式断言（避免 structural typing 报错）
 *  - links 缓存由对象改为 Map；TokensList 改为继承 Array 的 class
 *
 * 对外统一封装见 service/MarkdownParser.ets（markdownToHtml / markdownToText / HIGHLIGHT_CSS）。
 */

 import type { MarkedOptions } from './MarkedOptions';

/**
 * Gets the original marked default options.
 */
export function _getDefaults(): MarkedOptions {
  return {
    async: false,
    breaks: false,
    gfm: true,
    hooks: null,
    pedantic: false,
    renderer: null,
    silent: false,
    tokenizer: null,
    walkTokens: null
  };
}

export let _defaults = _getDefaults();

export function changeDefaults(newDefaults: MarkedOptions) {
  _defaults = newDefaults;
}

/**
 * Markdown 解析封装（marked 的 ArkTS 移植）
 *
 * 引入来源：https://github.com/electronicminer/Harmony-Markdown-Editor （MIT 协议）
 * 该仓库为 HarmonyOS 原生 Markdown 编辑器，其渲染引擎是 marked（github.com/markedjs/marked）
 * 的 ArkTS 移植版本，位于仓库 Markdown/src/main/ets/core/ 目录。
 * 本工程将其解析核心（Lexer / Parser / Tokenizer / Renderer / rules 等纯 TS 文件）提取出来，
 * 做 ArkTS 严格模式兼容改造后放于 common/markdown/ 目录（详见该目录顶部注释）。
 *
 * 用途：供分享（HTML/PDF/纯文本）使用，替代手写的轻量 markdownToHtml/stripMarkdown：
 *  - marked.parse()：Markdown → HTML（完整 GFM：表格/删除线/嵌套列表/任务列表等）
 *  - 代码块通过 HighlightAnalyzer 做轻量语法高亮（包 <span class="hl-xxx">）
 *  - 纯文本：走 TextRenderer（复用同一套 tokens，避免单独写 stripMarkdown）
 *
 * 依赖 common/markdown/ 下的 marked ArkTS 移植源码（MIT 协议）
 */
import { Marked } from '../common/markdown/Instance';
import { _TextRenderer } from '../common/markdown/TextRenderer';
import { _Lexer } from '../common/markdown/Lexer';
import { _Parser } from '../common/markdown/Parser';
import { _Renderer } from '../common/markdown/Renderer';
import { escape } from '../common/markdown/helpers';
import { highlightCodeAnalyzer, CodeToken } from '../common/markdown/analyzer/HighlightAnalyzer';
import type { Tokens } from '../common/markdown/Tokens';
import type { MarkedOptions } from '../common/markdown/MarkedOptions';

/** 高亮 CSS：浅色主题，关键字/类型/数字/字符串/符号/布尔 各自着色 */
export const HIGHLIGHT_CSS: string = `
.hl-keyword { color: #CF222E; }
.hl-type { color: #8250DF; }
.hl-number { color: #0550AE; }
.hl-string { color: #0A3069; }
.hl-symbol { color: #57606A; }
.hl-boolean { color: #0550AE; }
.hl-text { color: #1A1A1A; }
`;

/** 用 HighlightAnalyzer 分词后按类型包 <span>（代码块高亮） */
function highlightCode(code: string): string {
  const tokens: CodeToken[] = highlightCodeAnalyzer(code);
  let out: string = '';
  for (const t of tokens) {
    out += `<span class="hl-${t.type}">${escape(t.text)}</span>`;
  }
  return out;
}

/** 覆写 Renderer.code：对代码块内容做语法高亮（保留语言 class） */
class HighlightRenderer extends _Renderer {
  code(token: Tokens.Code): string {
    const langString = (token.lang || '').match(/^\S*/)?.[0] ?? '';
    const code = token.text.replace(/\n$/, '') + '\n';
    const body = langString.length > 0 ? highlightCode(code) : escape(code, true);
    const cls = langString.length > 0 ? ` class="language-${escape(langString)}"` : '';
    return `<pre><code${cls}>${body}</code></pre>\n`;
  }
}

/** 单例 Marked 实例：启用 GFM + 代码高亮 renderer */
const markdown: Marked = new Marked({
  gfm: true,
  breaks: false,
  renderer: new HighlightRenderer(),
} as MarkedOptions);

/**
 * Markdown → HTML 字符串（供 HTML/PDF 分享；同步解析，返回 string）
 */
export function markdownToHtml(md: string): string {
  return markdown.parse(md);
}

/**
 * Markdown → 纯文本（去掉所有标记，供纯文本分享）
 * 用同一套 Lexer/Parser 走 TextRenderer，准确剥离标题/列表/代码/链接等语法
 */
export function markdownToText(md: string): string {
  const tokens = _Lexer.lex(md, { gfm: true });
  const parser = new _Parser({ gfm: true } as MarkedOptions);
  return parser.parse(tokens);
}

import type { Tokens } from './Tokens';

/**
 * 解码常见 HTML 实体（纯文本输出用）
 * &amp; 最后解码：避免 &amp;lt; 等二次展开后又被 < 规则误处理
 */
function decodeEntities(s: string): string {
  return s
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&');
}

/** 剥离 HTML 标签，仅保留标签间文字（纯文本输出用；代码块不经过此方法） */
function stripTags(s: string): string {
  return s.replace(/<[^>]*>/g, '');
}

/**
 * TextRenderer（ArkTS 适配版）
 * returns only the textual part of the token
 * 供 MarkdownParser.markdownToText 使用：剥离 Markdown 标记与 HTML 标签、
 * 解码 HTML 实体，输出干净的纯文本
 */
export class _TextRenderer {
  // no need for block level renderers
  strong(token: Tokens.Strong): string {
    return decodeEntities(token.text);
  }

  em(token: Tokens.Em): string {
    return decodeEntities(token.text);
  }

  codespan(token: Tokens.Codespan): string {
    return token.text;
  }

  del(token: Tokens.Del): string {
    return decodeEntities(token.text);
  }

  html(token: Tokens.HTML | Tokens.Tag): string {
    return stripTags(token.text);
  }

  text(token: Tokens.Text | Tokens.Escape | Tokens.Tag): string {
    return decodeEntities(token.text);
  }

  link(token: Tokens.Link): string {
    return decodeEntities(token.text);
  }

  image(token: Tokens.Image): string {
    return decodeEntities(token.text);
  }

  br(): string {
    return '';
  }
}

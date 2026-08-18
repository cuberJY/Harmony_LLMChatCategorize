import type { Tokens } from './Tokens';

/**
 * TextRenderer（ArkTS 适配版）
 * returns only the textual part of the token
 */
export class _TextRenderer {
  // no need for block level renderers
  strong(token: Tokens.Strong): string {
    return token.text;
  }

  em(token: Tokens.Em): string {
    return token.text;
  }

  codespan(token: Tokens.Codespan): string {
    return token.text;
  }

  del(token: Tokens.Del): string {
    return token.text;
  }

  html(token: Tokens.HTML | Tokens.Tag): string {
    return token.text;
  }

  text(token: Tokens.Text | Tokens.Escape | Tokens.Tag): string {
    return token.text;
  }

  link(token: Tokens.Link): string {
    return '' + token.text;
  }

  image(token: Tokens.Image): string {
    return '' + token.text;
  }

  br(): string {
    return '';
  }
}

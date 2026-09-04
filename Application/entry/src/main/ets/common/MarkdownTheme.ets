/**
 * Markdown 渲染主题配置（@luvi/lv-markdown-in）—— 统一工具
 * 聊天消息气泡与 Markdown 文件预览页共用同一套主题配置，保证渲染效果一致。
 *
 * 说明：
 *  - 字体类颜色传 $r() 资源引用，系统自动在深浅色切换时加载 dark/ 目录对应色值（无需代码干预）
 *  - 代码块/思维导图主题只能传字符串 'light'/'dark'，必须由调用方监听系统 colorMode 手动切换
 *  - LaTeX 公式颜色只能传十六进制 number（公式渲染为 pixelMap 位图，库不支持 $r 引用），同样手动切换
 */
import { MarkdownController } from "@luvi/lv-markdown-in";

/**
 * 应用 Markdown 主题（颜色 / 字号 / 代码块 / 公式 / 思维导图）
 * @param controller 目标 MarkdownController
 * @param isDark 是否深色模式（决定代码块/思维导图主题与公式颜色）
 */
export function applyMarkdownTheme(controller: MarkdownController, isDark: boolean): void {
  /* 链式部分（返回 this 的 setter） */
  const c = controller
    .setLazyRender(true) // 屏幕外块先用轻量占位渲染
    .setLazyPreloadBlockCount(2) // 仅预渲染可视区附近少量块
    .setThreadRenderEnable(true) // 线程渲染（默认已开，可显式声明）
    .setTitleColor($r('app.color.font_primary'))
    .setTextColor($r('app.color.font_primary'))
    .setInlineCodeColor($r('app.color.font_emphasize'))
    .setInlineCodeBackgroundColor($r('app.color.bubble_bg_thinking'))
    .setQuoteTextColor($r('app.color.font_secondary'))
    .setQuoteBorderColor($r('app.color.divider'))
    .setQuoteBackgroundColor($r('app.color.bubble_bg_thinking'))
    .setHyperlinkTextColor($r('app.color.font_emphasize'))
    .setHyperlinkBackgroundColor(Color.Transparent)
    .setTableTitleTextColor($r('app.color.font_primary'))
    .setTableTitleBackgroundColor($r('app.color.bubble_bg_thinking'))
    .setTableBackgroundColor($r('app.color.bubble_bg_ai'))
    .setTableInterleaveBackgroundColor($r('app.color.bubble_bg_thinking'))
    .setTableOuterBorderColor($r('app.color.divider'))
    .setTableInnerBorderColor($r('app.color.divider'))
    .setTodoSelectedColor($r('app.color.font_emphasize'))
    .setUlPointColor($r('app.color.font_secondary'))
    .setFootnoteTextColor($r('app.color.font_secondary'))
    .setLineColor($r('app.color.divider'))
    /* 字号统一（float.json 资源管理） */
    .setTextSize($r('app.float.font_body')) // 正文 = font_body，与用户消息一致
    .setTitleSize([ // 标题 1-6 级字号
      $r('app.float.font_h1'),
      $r('app.float.font_h2'),
      $r('app.float.font_h3'),
      $r('app.float.font_h4'),
      $r('app.float.font_h5'),
      $r('app.float.font_h6'),
    ])
    .setLatexMathTextSize(16) // 公式字号
    /* LaTeX 公式颜色：库只接受十六进制 number，手动随系统深浅色切换 */
    .setLatexMathTextColor(isDark ? 0xFFE5E5E7 : 0xFF1A1A1A)
    .setCodeBlockTheme(isDark ? 'dark' : 'light')
    .setCodeBlockIdxState(true) // 代码块是否显示行号索引（可减少渲染节点，提升长代码块滚动性能）
    .setCodeBlockAutoCollapseEnable(true) // 超过阈值(默认10行)的代码块自动折叠
    .setMermaidTheme(isDark ? 'dark' : 'light');
  /* 以下两个 setter 返回 void，不能链式调用，需单独设置 */
  c.setTableNormalTextColor($r('app.color.font_primary'));
  c.setTableInterleaveTextColor($r('app.color.font_secondary'));
}

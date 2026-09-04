/**
 * 分享服务层
 * 封装系统 Share Kit API，支持多种分享格式（文本/HTML/图片/PDF），
 * 提供对话内容格式化与系统分享面板调用能力。
 *
 * 格式支持：
 *   - PLAIN_TEXT：纯文本，所有分享目标通用
 *   - HTML：富文本（当前实现），保留加粗/标题等格式
 *   - IMAGE：图片截图分享（ShareSheetPanel 组件截图卡片 → PNG 文件）
 *   - PDF：多页 A4 PDF 分享（PdfExporter 把卡片长图切分并嵌入 PDF，无需 ArkWeb createPdf）
 */

import { common } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { Message } from '../model/Message';
import { Logger } from '../common/Logger';
import { markdownToHtml, markdownToText, HIGHLIGHT_CSS } from './MarkdownParser';
import {
  SHARE_CARD_BG,
  SHARE_TEXT_PRIMARY,
  SHARE_USER_BUBBLE_BG,
  SHARE_AI_BUBBLE_BG,
  SHARE_PAGE_BG,
} from '../common/ShareStyle';

/** 分享格式枚举 */
export enum ShareFormat {
  PLAIN_TEXT = 'plain_text',
  MARKDOWN = 'markdown',
  HTML = 'html',
  IMAGE = 'image',
  PDF = 'pdf',
}

export class ShareService {
  /**
   * 分享内容（通用入口）
   * @param context UIAbilityContext
   * @param content 分享内容（纯文本或 HTML 字符串）
   * @param format 分享格式
   * @param title 分享标题（用于系统分享面板预览）
   */
  static async share(context: common.UIAbilityContext, content: string, format: ShareFormat, title: string): Promise<void> {
    try {
      if (format === ShareFormat.HTML) {
        /* HTML：生成 .html 文件后按文件分享（接收方收到的是文件，而非纯文本） */
        await ShareService.shareHtmlFile(context, content, title);
        return;
      }
      if (format === ShareFormat.MARKDOWN) {
        /* Markdown：生成 .md 文件后按文件分享（保留原始标记，接收方用支持 MD 的应用打开） */
        await ShareService.shareMarkdownFile(context, content, title);
        return;
      }
      /* 纯文本：content 直接分享为文本 */
      const shareData = new systemShare.SharedData({
        utd: uniformTypeDescriptor.UniformDataType.PLAIN_TEXT,
        content: content,
        title: title,
        description: title,
      });
      ShareService.showPanel(context, shareData);
    } catch (e) {
      Logger.error(`ShareService.share failed: ${JSON.stringify(e)}`);
    }
  }

  /**
   * HTML 分享为文件：将 HTML 字符串写入应用缓存目录的 .html 文件，
   * 通过 uri 字段分享，接收方收到的是真实文件（可用浏览器/文档应用打开）
   */
  private static async shareHtmlFile(context: common.UIAbilityContext, html: string, title: string): Promise<void> {
    /* 文件名：去除标题中的非法文件名字符，过长则截断；标题为空时用时间戳兜底 */
    const safeName = title.replace(/[\\/:*?"<>|]/g, '_').slice(0, 30) || `chat_${Date.now()}`;
    const filePath = `${context.cacheDir}/${safeName}.html`;

    /* 写入 .html 文件（CREATE 建文件 + TRUNC 清空已有内容，避免重名残留旧内容） */
    const file = await fs.open(filePath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try {
      await fs.write(file.fd, html);
    } finally {
      await fs.close(file.fd);
    }

    /* 构造文件分享数据：uri 指向沙箱文件，utd 为 HTML 类型 */
    const shareData = new systemShare.SharedData({
      utd: uniformTypeDescriptor.UniformDataType.HTML,
      uri: fileUri.getUriFromPath(filePath),
      title: title,
      description: title,
    });
    ShareService.showPanel(context, shareData);
  }

  /** 拉起系统分享面板（统一封装预览模式与选择模式） */
  private static showPanel(context: common.UIAbilityContext, shareData: systemShare.SharedData): void {
    const controller = new systemShare.ShareController(shareData);
    controller.show(context, {
      previewMode: systemShare.SharePreviewMode.DEFAULT,
      selectionMode: systemShare.SelectionMode.SINGLE,
    });
  }

  /**
   * Markdown 分享为文件：将 Markdown 源码写入应用缓存目录的 .md 文件，
   * 通过 uri 字段按文件分享（接收方可用支持 Markdown 的应用/编辑器打开）
   * UTD 用 PLAIN_TEXT（系统无 markdown 类型），.md 后缀足以让接收方识别
   */
  private static async shareMarkdownFile(context: common.UIAbilityContext, md: string, title: string): Promise<void> {
    /* 文件名：去除标题中的非法文件名字符，过长则截断；标题为空时用时间戳兜底 */
    const safeName = title.replace(/[\\/:*?"<>|]/g, '_').slice(0, 30) || `chat_${Date.now()}`;
    const filePath = `${context.cacheDir}/${safeName}.md`;

    /* 写入 .md 文件（CREATE 建文件 + TRUNC 清空已有内容，避免重名残留旧内容） */
    const file = await fs.open(filePath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try {
      await fs.write(file.fd, md);
    } finally {
      await fs.close(file.fd);
    }

    /* 构造文件分享数据：uri 指向沙箱 .md 文件，utd 用纯文本类型 */
    const shareData = new systemShare.SharedData({
      utd: uniformTypeDescriptor.UniformDataType.PLAIN_TEXT,
      uri: fileUri.getUriFromPath(filePath),
      title: title,
      description: title,
    });
    ShareService.showPanel(context, shareData);
  }

  /**
   * 分享 PDF：直接分享已生成的 .pdf 文件（由 PdfExporter 写入应用缓存目录），
   * 通过 uri 字段按文件分享（接收方可用 PDF 阅读器 / 微信等打开）
   * @param context UIAbilityContext
   * @param pdfPath PDF 文件路径（页面侧由 PdfExporter.export 生成）
   * @param title 分享标题（用于系统分享面板预览）
   */
  static async sharePdfFile(context: common.UIAbilityContext, pdfPath: string, title: string): Promise<void> {
    try {
      /* 构造文件分享数据：uri 指向沙箱 PDF 文件，utd 用 Adobe PDF 类型（系统/微信可识别） */
      const shareData = new systemShare.SharedData({
        utd: 'com.adobe.pdf',
        uri: fileUri.getUriFromPath(pdfPath),
        title: title,
        description: title,
      });
      ShareService.showPanel(context, shareData);
    } catch (e) {
      Logger.error(`ShareService.sharePdfFile failed: ${JSON.stringify(e)}`);
    }
  }

  /**
   * 分享图片：将 PixelMap 打包为 PNG 写入应用缓存目录，
   * 通过 uri 字段按图片文件分享（接收方收到真实图片文件）
   * @param context UIAbilityContext
   * @param pixelMap 待分享的图片（Canvas 导出 / 截图等）
   * @param title 分享标题（用于系统分享面板预览）
   */
  static async sharePixelMap(context: common.UIAbilityContext, pixelMap: image.PixelMap, title: string): Promise<void> {
    try {
      /* PixelMap → PNG 编码（packer 必须释放，避免资源泄漏） */
      const packer = image.createImagePacker();
      const data: ArrayBuffer = await packer.packing(pixelMap, { format: 'image/png', quality: 100 });
      packer.release();

      /* 文件名：去除标题中的非法字符，过长截断；空标题用时间戳兜底 */
      const safeName = title.replace(/[\\/:*?"<>|]/g, '_').slice(0, 30) || `chat_${Date.now()}`;
      const filePath = `${context.cacheDir}/${safeName}.png`;

      /* 写入 PNG 文件（TRUNC 防止重名残留旧图） */
      const file = await fs.open(filePath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        await fs.write(file.fd, data);
      } finally {
        await fs.close(file.fd);
      }

      /* 构造图片分享数据：uri 指向沙箱 PNG 文件 */
      const shareData = new systemShare.SharedData({
        utd: uniformTypeDescriptor.UniformDataType.IMAGE,
        uri: fileUri.getUriFromPath(filePath),
        title: title,
        description: title,
      });
      ShareService.showPanel(context, shareData);
    } catch (e) {
      Logger.error(`ShareService.sharePixelMap failed: ${JSON.stringify(e)}`);
    }
  }

  /**
   * HTML 卡片排版
   * 内联样式常量
   * 不使用 <style> 标签而是写在每个元素的内联 style 上：RichText 预览不解析 <style>，
   * 会导致标题 margin 失效而重叠；内联样式在 RichText 与浏览器/文档应用中都生效
   */
  /* 卡片容器：圆角浅灰卡片，居中（颜色统一引用 common/ShareStyle） */
  private static readonly CARD_STYLE: string =
    `max-width:600px;margin:0 auto;background:${SHARE_CARD_BG};border-radius:16px;padding:20px;`;
  /* 卡片标题：居中加粗，下边距 16px（RichText 依赖此 margin 与消息分隔，避免重叠） */
  private static readonly TITLE_STYLE: string =
    `text-align:center;font-weight:700;font-size:18px;color:${SHARE_TEXT_PRIMARY};margin:0 0 16px;word-break:break-word;`;
  /* 消息行样式（左对齐），行间下边距 12px */
  private static readonly MSG_USER_STYLE: string = 'text-align:left;margin-bottom:12px;';
  private static readonly MSG_AI_STYLE: string = 'text-align:left;margin-bottom:12px;';
  /* 气泡通用样式（背景色由调用处追加，颜色统一引用 common/ShareStyle） */
  private static readonly BUBBLE_STYLE: string =
    `display:inline-block;max-width:540px;padding:12px 16px;border-radius:8px;` +
    `font-size:12px;line-height:18px;color:${SHARE_TEXT_PRIMARY};text-align:left;word-break:break-word;`;

  /**
   * 格式化整段对话为纯文本
   * 格式：
   *   [对话标题]
   *
   *   用户：
   *     xxx
   *   AI：
   *     xxx
   */
  static formatConversationAsText(messages: Message[], convTitle: string): string {
    const lines: string[] = [];
    lines.push(`[${convTitle}]`);
    lines.push('');

    for (const msg of messages) {
      if (msg.isUser()) {
        lines.push(`用户：`);
        lines.push(`${markdownToText(msg.content)}`);
      } else {
        /* AI 消息：Markdown → 纯文本（剥离 ##、** 等标记与 HTML 实体，后续再加 markdown 分享） */
        lines.push(`AI：`);
        lines.push(`${markdownToText(msg.content)}`);
      }
      lines.push('');
    }

    return lines.join('\n').trim();
  }

  /**
   * 格式化整段对话为 Markdown 源码（保留原始标记，供 .md 文件分享）
   * 格式：
   *   # [对话标题]
   *
   *   **用户：**
   *   [原始 Markdown 内容]
   *
   *   **AI：**
   *   [原始 Markdown 内容]
   */
  static formatConversationAsMarkdown(messages: Message[], convTitle: string): string {
    const lines: string[] = [];
    lines.push(`# ${convTitle}`);
    lines.push('');

    for (const msg of messages) {
      if (msg.isUser()) {
        lines.push(`**用户：**`);
      } else {
        lines.push(`**AI：**`);
      }
      /* 内容保留原始 Markdown 原文，不做任何转换 */
      lines.push(msg.content);
      lines.push('');
    }

    return lines.join('\n').trim();
  }

  /**
   * 格式化整段对话为 HTML（图片卡片样式，内联样式）
   * 结构与图片卡片一致：居中标题 + 用户右对齐浅蓝气泡 + AI 左对齐白气泡，
   * AI 内容做轻量 Markdown 转换（标题/加粗/代码块/引用/列表）
   */
  static formatConversationAsHtml(messages: Message[], convTitle: string): string {
    const parts: string[] = [];
    parts.push(`<div class="share-card" style="${ShareService.CARD_STYLE}">`);
    parts.push(`<div style="${ShareService.TITLE_STYLE}">${ShareService.escapeHtml(convTitle)}</div>`);

    for (const msg of messages) {
      if (msg.isUser()) {
        /* 用户消息：纯文本转义（换行转 <br>），右对齐浅蓝气泡 */
        parts.push(`<div style="${ShareService.MSG_USER_STYLE}"><div class="share-bubble" style="${ShareService.BUBBLE_STYLE}background:${SHARE_USER_BUBBLE_BG};">${ShareService.escapeHtml(msg.content)}</div></div>`);
      } else {
        /* AI 消息：Markdown → HTML（新 marked 解析器，完整 GFM + 代码高亮），左对齐白气泡 */
        parts.push(`<div style="${ShareService.MSG_AI_STYLE}"><div class="share-bubble" style="${ShareService.BUBBLE_STYLE}background:${SHARE_AI_BUBBLE_BG};">${markdownToHtml(msg.content)}</div></div>`);
      }
    }

    parts.push(`</div>`);
    return `<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><style>${HIGHLIGHT_CSS}</style></head><body style="margin:0;padding:16px;background:${SHARE_PAGE_BG};font-family:sans-serif;">${parts.join('')}</body></html>`;
  }

  /**
   * 格式化单次问答为纯文本
   * 格式：
   *   用户：xxx
   *   AI：xxx
   */
  static formatQAPairAsText(userMsg: Message, aiMsg: Message): string {
    const lines: string[] = [];
    lines.push(`用户：${markdownToText(userMsg.content)}`);
    lines.push('');
    lines.push(`AI：${markdownToText(aiMsg.content)}`);
    return lines.join('\n');
  }

  /**
   * 格式化单次问答为 Markdown 源码（保留原始标记，供 .md 文件分享）
   * 格式：
   *   **用户：**
   *   [原始 Markdown 内容]
   *
   *   **AI：**
   *   [原始 Markdown 内容]
   */
  static formatQAPairAsMarkdown(userMsg: Message, aiMsg: Message): string {
    const lines: string[] = [];
    lines.push(`**用户：**`);
    lines.push(userMsg.content);
    lines.push('');
    lines.push(`**AI：**`);
    lines.push(aiMsg.content);
    return lines.join('\n').trim();
  }

  /**
   * 格式化单次问答为 HTML（图片卡片样式，内联样式，同 formatConversationAsHtml）
   */
  static formatQAPairAsHtml(userMsg: Message, aiMsg: Message): string {
    return `<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><style>${HIGHLIGHT_CSS}</style></head><body style="margin:0;padding:16px;background:${SHARE_PAGE_BG};font-family:sans-serif;">
<div class="share-card" style="${ShareService.CARD_STYLE}">
<div style="${ShareService.TITLE_STYLE}">分享问答</div>
<div style="${ShareService.MSG_USER_STYLE}"><div class="share-bubble" style="${ShareService.BUBBLE_STYLE}background:${SHARE_USER_BUBBLE_BG};">${ShareService.escapeHtml(userMsg.content)}</div></div>
<div style="${ShareService.MSG_AI_STYLE}"><div class="share-bubble" style="${ShareService.BUBBLE_STYLE}background:${SHARE_AI_BUBBLE_BG};">${markdownToHtml(aiMsg.content)}</div></div>
</div>
</body></html>`;
  }

  /* 轻量 Markdown → HTML 转换（供 HTML 分享使用，覆盖常见语法即可） */

  /** HTML 转义（&、<、>；换行转 <br>，供纯文本气泡使用） */
  private static escapeHtml(s: string): string {
    return s
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/\n/g, '<br>');
  }
}
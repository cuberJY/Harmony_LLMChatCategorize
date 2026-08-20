/**
 * 分享半模态面板组件
 * 用于"分享对话"和"分享问答"时预览内容并选择格式
 * 由页面通过 bindSheet 弹出（弹层生命周期与页面绑定）
 *
 * 结构（从上到下）：
 *  标题行（"分享" + 关闭按钮）
 *  格式切换（纯文本 / HTML / 图片 / PDF）
 *  内容预览（纯文本 → Text；HTML → RichText；图片/PDF → ArkUI 组件排版的聊天卡片）
 *  底部「分享」按钮（选择格式后点击调用系统分享面板）
 *
 * 图片分享：用 ArkUI 组件渲染聊天卡片（标题 + 用户右对齐浅蓝气泡 /
 * AI 左对齐白气泡），排版由 ArkUI 引擎自动换行、对齐，保证整洁；
 * 分享时用 componentSnapshot 截取卡片为 PixelMap，页面写文件后按图片分享
 *
 * PDF 分享：与图片同一张卡片截图，但交给 PdfExporter 把长图按 A4 页高
 * 切分并用 PDF Kit 嵌入为多页 PDF 文件（放弃 ArkWeb createPdf：窄屏布局
 * 导出 A4 会排版混乱、分页错乱、末尾空白，多次修复不可靠）
 */

import { image } from '@kit.ImageKit';
import { ShareFormat } from '../../service/ShareService';
import { Markdown, MarkdownController } from "@luvi/lv-markdown-in";
import {
  SHARE_CARD_BG,
  SHARE_TEXT_PRIMARY,
  SHARE_USER_BUBBLE_BG,
  SHARE_AI_BUBBLE_BG,
  SHARE_HINT_TEXT,
  SHARE_INLINE_CODE_COLOR,
  SHARE_INLINE_CODE_BG,
  SHARE_QUOTE_TEXT_COLOR,
  SHARE_QUOTE_BORDER_COLOR,
} from '../../common/ShareStyle';

/** 图片卡片单条消息（role + 内容：用户消息为纯文本，AI 消息为 Markdown 原文） */
export interface ShareCardItem {
  role: 'user' | 'assistant'; // 消息角色
  content: string; // 用户消息纯文本；AI 消息 Markdown 原文（卡片内用 Markdown 组件渲染）
}

/** 图片卡片数据（页面侧由消息列表组装后传入） */
export interface ShareCardData {
  title: string; // 卡片标题
  items: ShareCardItem[]; // 消息列表（顺序即对话顺序）
}

/* 卡片排版常量（vp） */
const CARD_WIDTH: number = 340; // 卡片宽度（固定，保证截图比例稳定）
const CARD_RADIUS: number = 16; // 卡片圆角
const TITLE_FONT: number = 18; // 标题字号
const BODY_FONT: number = 16; // 正文字号
const USER_BUBBLE_MAX_WIDTH: number = 260; // 用户气泡最大宽度
const AI_BUBBLE_MAX_WIDTH: number = 300; // AI 气泡最大宽度
const BUBBLE_RADIUS: number = 16; // 气泡圆角
/* 颜色统一引用 common/ShareStyle（与 HTML 分享卡片保持一致） */
const CARD_BG: string = SHARE_CARD_BG; // 卡片背景（浅灰）
const USER_BUBBLE_BG: string = SHARE_USER_BUBBLE_BG; // 用户气泡（浅蓝）
const AI_BUBBLE_BG: string = SHARE_AI_BUBBLE_BG; // AI 气泡（白）

@ComponentV2
export struct ShareSheetPanel {
  @Param previewText: string = ""; // 纯文本预览内容
  @Param previewMarkdown: string = ""; // Markdown 源码预览内容（.md 文件分享）
  @Param previewHtml: string = ""; // HTML 预览内容
  @Param cardData: ShareCardData | null = null; // 图片卡片数据（null 时图片 tab 显示空态）
  @Param shareTitle: string = ""; // 分享标题（PDF 文件命名用，页面传入 shareSheetTitle）
  @Local selectedFormat: ShareFormat = ShareFormat.PLAIN_TEXT; // 当前选中格式（默认纯文本）

  /* AI 消息 Markdown 渲染控制器（预览首轮卡片固定浅色主题，导出卡片由宿主页面 ExportCardLayer 渲染） */
  private mdController: MarkdownController = new MarkdownController();

  /* 回调 */
  @Event onShare: (format: ShareFormat, pixelMap?: image.PixelMap, pdfPath?: string) => void =
    (format: ShareFormat, pixelMap?: image.PixelMap, pdfPath?: string) => {}; // 点击「分享」按钮（图片带 PixelMap / PDF 带生成的文件路径）
  @Event onExportRequest: (format: ShareFormat) => void = () => {}; // 图片/PDF 导出请求（弹层内无法截图，交宿主页面处理）
  @Event onClose: () => void = () => {}; // 关闭面板

  aboutToAppear(): void {
    /* 配置卡片内 Markdown 样式：固定浅色；关闭懒渲染确保截图时全部内容已渲染（线程渲染完成会触发 callback.complete） */
    this.mdController
      .setLazyRender(false)
      .setThreadRenderEnable(true)
      .setTextColor(SHARE_TEXT_PRIMARY)
      .setTextSize(BODY_FONT)
      .setTextLineHeight(22)
      .setTitleColor(SHARE_TEXT_PRIMARY)
      .setInlineCodeColor(SHARE_INLINE_CODE_COLOR)
      .setInlineCodeBackgroundColor(SHARE_INLINE_CODE_BG)
      .setQuoteTextColor(SHARE_QUOTE_TEXT_COLOR)
      .setQuoteBorderColor(SHARE_QUOTE_BORDER_COLOR)
      .setCodeBlockTheme('light')
      .setMermaidTheme('light');
  }

  build() {
    Column() {
      /* 标题行：居中标题 + 右上角关闭按钮（与「选择文本」面板一致） */
      Row() {
        Row().width($r('app.float.space_xxl'))
        Text("分享")
          .fontSize($r('app.float.font_title'))
          .fontWeight(700)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Row() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize($r('app.float.font_icon_lg'))
            .fontWeight(700)
            .fontColor([$r('app.color.text_primary')])
        }
        .width($r('app.float.space_xxl'))
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.onClose();
        })
      }
      .width("100%")
      .height($r('app.float.title_bar_height'))
      .padding({
        left: $r('app.float.space_xl'),
        right: $r('app.float.space_xl'),
      })
      .border({
        width: { bottom: 2 },
        color: { bottom: $r('app.color.divider') },
      })

      /* 格式切换：纯文本 / HTML / 图片 分段控件 */
      Row() {
        Text("文本")
          .fontSize($r('app.float.font_toggle'))
          .fontColor(
            this.selectedFormat === ShareFormat.PLAIN_TEXT ? $r('app.color.toggle_text_active') : $r('app.color.toggle_text_inactive'),
          )
          .fontWeight(this.selectedFormat === ShareFormat.PLAIN_TEXT ? 700 : 400)
          .padding({
            left: $r('app.float.space_md'),
            right: $r('app.float.space_md'),
            top: $r('app.float.space_xs'),
            bottom: $r('app.float.space_xs'),
          })
          .backgroundColor(this.selectedFormat === ShareFormat.PLAIN_TEXT ? $r('app.color.toggle_bg_active') : Color.Transparent)
          .height(36)
          .width(64)
          .borderRadius(18)
          .textAlign(TextAlign.Center)
          .margin({
            left: $r('app.float.space_xxs'),
            right: $r('app.float.space_xxs'),
          })
          .onClick(() => {
            this.selectedFormat = ShareFormat.PLAIN_TEXT;
          })

        Text("MD")
          .fontSize($r('app.float.font_toggle'))
          .fontColor(
            this.selectedFormat === ShareFormat.MARKDOWN ? $r('app.color.toggle_text_active') : $r('app.color.toggle_text_inactive'),
          )
          .fontWeight(this.selectedFormat === ShareFormat.MARKDOWN ? 700 : 400)
          .padding({
            left: $r('app.float.space_md'),
            right: $r('app.float.space_md'),
            top: $r('app.float.space_xs'),
            bottom: $r('app.float.space_xs'),
          })
          .backgroundColor(this.selectedFormat === ShareFormat.MARKDOWN ? $r('app.color.toggle_bg_active') : Color.Transparent)
          .height(36)
          .width(64)
          .borderRadius(18)
          .textAlign(TextAlign.Center)
          .margin({
            left: $r('app.float.space_xxs'),
            right: $r('app.float.space_xxs'),
          })
          .onClick(() => {
            this.selectedFormat = ShareFormat.MARKDOWN;
          })

        Text("HTML")
          .fontSize($r('app.float.font_toggle'))
          .fontColor(
            this.selectedFormat === ShareFormat.HTML ? $r('app.color.toggle_text_active') : $r('app.color.toggle_text_inactive'),
          )
          .fontWeight(this.selectedFormat === ShareFormat.HTML ? 700 : 400)
          .padding({
            left: $r('app.float.space_sm'),
            right: $r('app.float.space_sm'),
            top: $r('app.float.space_xs'),
            bottom: $r('app.float.space_xs'),
          })
          .backgroundColor(this.selectedFormat === ShareFormat.HTML ? $r('app.color.toggle_bg_active') : Color.Transparent)
          .height(36)
          .width(64)
          .borderRadius(18)
          .textAlign(TextAlign.Center)
          .margin({
            left: $r('app.float.space_xxs'),
            right: $r('app.float.space_xxs'),
          })
          .onClick(() => {
            this.selectedFormat = ShareFormat.HTML;
          })

        Text("图片")
          .fontSize($r('app.float.font_toggle'))
          .fontColor(
            this.selectedFormat === ShareFormat.IMAGE ? $r('app.color.toggle_text_active') : $r('app.color.toggle_text_inactive'),
          )
          .fontWeight(this.selectedFormat === ShareFormat.IMAGE ? 700 : 400)
          .padding({
            left: $r('app.float.space_md'),
            right: $r('app.float.space_md'),
            top: $r('app.float.space_xs'),
            bottom: $r('app.float.space_xs'),
          })
          .backgroundColor(this.selectedFormat === ShareFormat.IMAGE ? $r('app.color.toggle_bg_active') : Color.Transparent)
          .height(36)
          .width(64)
          .borderRadius(18)
          .textAlign(TextAlign.Center)
          .margin({
            left: $r('app.float.space_xxs'),
            right: $r('app.float.space_xxs'),
          })
          .onClick(() => {
            this.selectedFormat = ShareFormat.IMAGE;
          })

        Text("PDF")
          .fontSize($r('app.float.font_toggle'))
          .fontColor(
            this.selectedFormat === ShareFormat.PDF ? $r('app.color.toggle_text_active') : $r('app.color.toggle_text_inactive'),
          )
          .fontWeight(this.selectedFormat === ShareFormat.PDF ? 700 : 400)
          .padding({
            left: $r('app.float.space_md'),
            right: $r('app.float.space_md'),
            top: $r('app.float.space_xs'),
            bottom: $r('app.float.space_xs'),
          })
          .backgroundColor(this.selectedFormat === ShareFormat.PDF ? $r('app.color.toggle_bg_active') : Color.Transparent)
          .height(36)
          .width(64)
          .borderRadius(18)
          .textAlign(TextAlign.Center)
          .margin({
            left: $r('app.float.space_xxs'),
            right: $r('app.float.space_xxs'),
          })
          .onClick(() => {
            this.selectedFormat = ShareFormat.PDF;
          })
      }
      .width("100%")
      .justifyContent(FlexAlign.Center)
      .padding({
        top: $r('app.float.space_sm'),
        bottom: $r('app.float.space_sm'),
      })

      /* 内容预览区（layoutWeight 撑满剩余空间） */
      Column() {
        if (this.selectedFormat === ShareFormat.PLAIN_TEXT) {
          /* 纯文本预览：只读文本，可滚动 */
          Scroll() {
            Text(this.previewText)
              .fontSize($r('app.float.font_body'))
              .fontColor($r('app.color.text_ai'))
              .copyOption(CopyOptions.LocalDevice)
              .width("100%")
              .padding({
                left: $r('app.float.space_xl'),
                right: $r('app.float.space_xl'),
                top: $r('app.float.space_md'),
                bottom: $r('app.float.space_md'),
              })
          }
          .width("100%")
          .height("100%")
          .align(Alignment.TopStart)
          .scrollBar(BarState.Auto)
        } else if (this.selectedFormat === ShareFormat.MARKDOWN) {
          /* Markdown 源码预览：原文只读文本，可长按复制（与纯文本预览同样式） */
          Scroll() {
            Text(this.previewMarkdown)
              .fontSize($r('app.float.font_body'))
              .fontColor($r('app.color.text_ai'))
              .copyOption(CopyOptions.LocalDevice)
              .width("100%")
              .padding({
                left: $r('app.float.space_xl'),
                right: $r('app.float.space_xl'),
                top: $r('app.float.space_md'),
                bottom: $r('app.float.space_md'),
              })
          }
          .width("100%")
          .height("100%")
          .align(Alignment.TopStart)
          .scrollBar(BarState.Auto)
        } else if (this.selectedFormat === ShareFormat.HTML) {
          /* HTML 预览：RichText 渲染 HTML 字符串（仅内容区内部滚动，不影响整个面板） */
          Scroll() {
            RichText(this.previewHtml)
              .width("100%")
          }
          .width("100%")
          .height("100%")
          .align(Alignment.TopStart)
          .scrollBar(BarState.Auto)
        } else {
          /* 图片 / PDF 预览：轻量首轮样式卡（不渲染完整内容，保证半模态触控不卡顿）。
             完整内容由宿主页面 ExportCardLayer 在点「分享」时挂载隐藏分段卡片渲染 + 页面级截图
             （弹层内 componentSnapshot 截图不可用，get 报 100001） */
          Scroll() {
            Column() {
              if (this.cardData !== null) {
                this.previewCard(this.cardData)
                Text("预览仅展示首轮，分享时完整生成")
                  .fontSize($r('app.float.font_remind'))
                  .fontColor(SHARE_HINT_TEXT)
                  .margin({
                    top: $r('app.float.space_md'),
                    bottom: $r('app.float.space_md'),
                  })
              } else {
                Text("暂无分享内容")
                  .fontSize($r('app.float.font_remind'))
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ top: $r('app.float.space_lg') })
              }
            }
            .width("100%")
            .alignItems(HorizontalAlign.Center)
            .padding({
              top: $r('app.float.space_md'),
              bottom: $r('app.float.space_md'),
            })
          }
          .width("100%")
          .height("100%")
          .align(Alignment.TopStart)
          .scrollBar(BarState.Auto)
        }
      }
      .width("100%")
      .layoutWeight(1)
      .backgroundColor($r('app.color.page_bg'))

      /* 底部「分享」按钮 */
      Button() {
        Row() {
          SymbolGlyph($r('sys.symbol.share'))
            .fontSize($r('app.float.font_icon_lg'))
            .fontWeight(700)
            .fontColor([Color.White])
            .margin({ right: $r('app.float.space_sm') })
          Text("分享")
            .fontSize($r('app.float.font_button'))
            .fontColor(Color.White)
        }
        .justifyContent(FlexAlign.Center)
      }
      .width(80)
      .height(40)
      .borderRadius(20)
      .backgroundColor($r('app.color.primary'))
      .margin({
        top: $r('app.float.space_md'),
        bottom: $r('app.float.space_xxl'),
      })
      .onClick(() => {
        this.handleShareClick();
      })
    }
    .width("100%")
    .height("100%")
    .backgroundColor($r('app.color.dialog_bg'));
  }

  /* 图片卡片（ArkUI 组件排版） */

  /**
   * 轻量样式预览卡：仅展示首轮对话（用户消息 + AI 回复）示意最终效果。
   * AI 消息完整渲染 Markdown（真实富文本样式）；不渲染后续轮次 ——
   * 完整卡片在点「分享」时由宿主页面 ExportCardLayer 隐藏分段渲染，预览区保持轻量、触控不卡顿
   */
  @Builder
  previewCard(data: ShareCardData) {
    Column() {
      /* 卡片标题（居中加粗） */
      Text(data.title)
        .fontSize(TITLE_FONT)
        .fontWeight(700)
        .fontColor(SHARE_TEXT_PRIMARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ bottom: 16 })

      /* 首轮对话气泡（样式展示） */
      ForEach(this.previewItems(data.items), (item: ShareCardItem) => {
        /* 用户消息右对齐 / AI 消息左对齐 */
        Row() {
          if (item.role === 'user') {
            Blank()
          }
          Column() {
            if (item.role === 'user') {
              /* 用户消息：纯文本 */
              Text(item.content)
                .fontSize(BODY_FONT)
                .fontColor(SHARE_TEXT_PRIMARY)
                .lineHeight(22)
                .copyOption(CopyOptions.None)
            } else {
              /* AI 消息：Markdown 组件渲染完整原文（真实富文本样式） */
              Markdown({
                text: item.content,
                mode: 'text',
                controller: this.mdController,
              })
            }
          }
          .padding({
            left: 14,
            right: 14,
            top: 10,
            bottom: 10,
          })
          .borderRadius(BUBBLE_RADIUS)
          .backgroundColor(item.role === 'user' ? USER_BUBBLE_BG : AI_BUBBLE_BG)
          .constraintSize({ maxWidth: item.role === 'user' ? USER_BUBBLE_MAX_WIDTH : AI_BUBBLE_MAX_WIDTH })
          if (item.role === 'assistant') {
            Blank()
          }
        }
        .width("100%")
        .alignItems(VerticalAlign.Top)
        .margin({ bottom: 14 })
      }, (item: ShareCardItem, index: number) => `${item.role}_${index}`)
    }
    .width(CARD_WIDTH)
    .padding(20)
    .borderRadius(CARD_RADIUS)
    .backgroundColor(CARD_BG)
  }

  /** 取首轮对话用于样式预览：第一条用户消息起，至下一条用户消息前；无用户消息时取第一条 */
  private previewItems(items: ShareCardItem[]): ShareCardItem[] {
    if (items.length === 0) {
      return [];
    }
    const first: ShareCardItem = items[0];
    if (first.role === 'assistant') {
      return [first];
    }
    const result: ShareCardItem[] = [first];
    for (let i = 1; i < items.length; i++) {
      if (items[i].role === 'user') {
        break;
      }
      result.push(items[i]);
    }
    return result;
  }

  /**
   * 分享按钮点击：
   *  - 图片 / PDF：弹层内 componentSnapshot 截图不可用（get 报 100001、createFromBuilder
   *    不支持 Markdown 三方组件），通过 onExportRequest 交宿主页面：页面挂载隐藏分段卡片
   *    （ExportCardLayer，页面级组件可截图）逐段截图后，图片拼接长图（ImageMerger）/
   *    PDF 生成多页（PdfExporter），完成后由页面拉起系统分享并关闭面板。
   *  - 文本/MD/HTML：直接回调。
   */
  private handleShareClick(): void {
    if (this.selectedFormat === ShareFormat.IMAGE || this.selectedFormat === ShareFormat.PDF) {
      if (this.cardData === null) {
        return; // 无内容不响应
      }
      /* 交宿主页面级导出，关闭面板（导出完成后页面直接拉起系统分享） */
      this.onExportRequest(this.selectedFormat);
      this.onClose();
      return;
    }
    this.onShare(this.selectedFormat);
  }
}
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
import { common } from '@kit.AbilityKit';
import { ShareFormat } from '../../service/ShareService';
import { PdfExporter } from '../../service/PdfExporter';
import { Markdown, MarkdownController } from "@luvi/lv-markdown-in";
import { showToast } from '../../common/Utils';
import {
  SHARE_CARD_BG,
  SHARE_TEXT_PRIMARY,
  SHARE_USER_BUBBLE_BG,
  SHARE_AI_BUBBLE_BG,
  SHARE_HINT_TEXT,
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
/* 卡片问答轮数上限：1 次问答 = 1 条用户消息及其回复。
   限制卡片高度，避免长对话截图过大/超长（超出部分用省略提示）。
   图片卡片受组件截图高度硬限制（约 16000px），取 10 轮稳妥；PDF 为分页文档可更长 */
const IMAGE_MAX_ROUNDS: number = 10; // 图片卡片最多问答轮数
const PDF_MAX_ROUNDS: number = 50; // PDF 卡片最多问答轮数

@ComponentV2
export struct ShareSheetPanel {
  @Param previewText: string = ""; // 纯文本预览内容
  @Param previewHtml: string = ""; // HTML 预览内容
  @Param cardData: ShareCardData | null = null; // 图片卡片数据（null 时图片 tab 显示空态）
  @Param shareTitle: string = ""; // 分享标题（PDF 文件命名用，页面传入 shareSheetTitle）
  @Local selectedFormat: ShareFormat = ShareFormat.PLAIN_TEXT; // 当前选中格式（默认纯文本）

  /* AI 消息 Markdown 渲染控制器（图片卡片固定浅色主题，截图白底与主题无关） */
  private mdController: MarkdownController = new MarkdownController();
  /* 卡片渲染稳定检测：Markdown 是异步渲染的，以「卡片高度超过阈值时间不再变化」作为渲染完成信号，
     截图前等待稳定，避免截到空白/未完成内容（不依赖三方库渲染回调，可靠） */
  @Local cardHeight: number = 0; // 卡片最近一次布局高度（onAreaChange 记录）
  @Local cardHeightTime: number = 0; // 最近一次高度变化时间戳（Date.now()）

  /* 回调 */
  @Event onShare: (format: ShareFormat, pixelMap?: image.PixelMap, pdfPath?: string) => void =
    (format: ShareFormat, pixelMap?: image.PixelMap, pdfPath?: string) => {}; // 点击「分享」按钮（图片带 PixelMap / PDF 带生成的文件路径）
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
      .setInlineCodeColor('#0A59F7')
      .setInlineCodeBackgroundColor('#F0F0F0')
      .setQuoteTextColor('#666666')
      .setQuoteBorderColor('#DDDDDD')
      .setCodeBlockTheme('light')
      .setMermaidTheme('light');
  }

  /**
   * 等待卡片渲染稳定：卡片高度出现后，超过 500ms 不再变化视为 Markdown 渲染完成
   * （最多等待上限防死等），超时后按当前状态继续截图。
   * 等待上限按格式区分：图片卡片内容少（10 轮）等 5s；PDF 卡片最多 50 轮、
   * Markdown 异步渲染更慢，放宽到 10s，避免长内容被截到未完成状态
   */
  private async waitCardReady(): Promise<void> {
    const waitMs: number = this.selectedFormat === ShareFormat.PDF ? 10000 : 5000;
    const deadline: number = Date.now() + waitMs;
    while (Date.now() < deadline) {
      if (this.cardHeight > 0 && Date.now() - this.cardHeightTime > 500) {
        return; // 高度稳定 → 渲染完成
      }
      await new Promise<void>((resolve: () => void) => {
        setTimeout(resolve, 50);
      });
    }
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
          /* 图片 / PDF 预览：ArkUI 组件排版的聊天卡片（真实排版，所见即所得）。
             PDF 与图片共用同一张卡片截图：PDF 分享时由 PdfExporter 把长图
             按 A4 页高切分嵌入多页 PDF 文件 */
          Scroll() {
            Column() {
              if (this.cardData !== null) {
                this.cardPreview(this.cardData)
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
   * 聊天卡片组件：设置固定 id 供 componentSnapshot 截图。
   * 卡片内部用 ArkUI 原生组件排版（Column/Row/Text），自动换行与对齐由引擎保证，
   * 不再手写 Canvas 换行算法，从根本上解决排版混乱问题。
   */
  @Builder
  cardPreview(data: ShareCardData) {
    Column() {
      /* 卡片标题（居中加粗） */
      Text(data.title)
        .fontSize(TITLE_FONT)
        .fontWeight(700)
        .fontColor(SHARE_TEXT_PRIMARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ bottom: 16 })

      /* 消息气泡列表 */
      ForEach(this.limitItems(data.items), (item: ShareCardItem) => {
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
              /* AI 消息：Markdown 组件渲染原文（标题/列表/代码块/公式等） */
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

      /* 超出问答轮数上限时提示（避免卡片过长） */
      if (this.countRounds(data.items) > this.getMaxRounds()) {
        Text(`… 共 ${this.countRounds(data.items)} 次问答，仅展示前 ${this.getMaxRounds()} 次`)
          .fontSize(12)
          .fontColor(SHARE_HINT_TEXT)
          .width("100%")
          .textAlign(TextAlign.Center)
          .margin({ bottom: 8 })
      }
    }
    .width(CARD_WIDTH)
    .padding(20)
    .borderRadius(CARD_RADIUS)
    .backgroundColor(CARD_BG)
    .id('shareCard') // componentSnapshot 截图锚点
    .onAreaChange((oldValue: Area, newValue: Area) => {
      /* 记录卡片高度与变化时间：高度连续稳定表示 Markdown 异步渲染已落地（截图前等待依据） */
      const h: number = Number(newValue.height);
      if (h > 0 && Math.abs(h - this.cardHeight) > 0.5) {
        this.cardHeight = h;
        this.cardHeightTime = Date.now();
      }
    })
  }

  /** 当前格式允许的最大问答轮数（图片卡片矮、PDF 为分页文档可更长） */
  private getMaxRounds(): number {
    return this.selectedFormat === ShareFormat.PDF ? PDF_MAX_ROUNDS : IMAGE_MAX_ROUNDS;
  }

  /** 统计消息列表中的问答轮数（用户消息条数 = 问答轮数） */
  private countRounds(items: ShareCardItem[]): number {
    let rounds: number = 0;
    for (const item of items) {
      if (item.role === 'user') {
        rounds++;
      }
    }
    return rounds;
  }

  /** 按问答轮数截取消息：保留前 maxRounds 条用户消息及其回复，超出部分丢弃 */
  private limitItems(items: ShareCardItem[]): ShareCardItem[] {
    const maxRounds: number = this.getMaxRounds();
    const result: ShareCardItem[] = [];
    let rounds: number = 0;
    for (const item of items) {
      if (item.role === 'user') {
        rounds++;
        if (rounds > maxRounds) {
          break;
        }
      }
      result.push(item);
    }
    return result;
  }

  /**
   * 分享按钮点击：图片/PDF 格式先等卡片渲染稳定（Markdown 异步渲染落地），
   * 再用 UIContext 组件截图截取卡片为 PixelMap；图片格式回调 PixelMap 由页面写文件分享，
   * PDF 格式交给 PdfExporter 把长图切分嵌入多页 A4 PDF 文件后回调文件路径分享；
   * 文本/HTML 格式直接回调。
   * 截图双保险：方式一 get(id) 截取已挂载组件（等待渲染完成）；
   * 方式二 createFromBuilder 离屏构建卡片再截图（不依赖组件挂树，弹层场景兜底）。
   * 均失败则 Toast 提示，避免点击无反馈
   */
  private async handleShareClick(): Promise<void> {
    if (this.selectedFormat === ShareFormat.IMAGE || this.selectedFormat === ShareFormat.PDF) {
      if (this.cardData === null) {
        return; // 无内容不响应
      }
      /* 等待 Markdown 渲染完成（卡片高度稳定，最多 3 秒） */
      await this.waitCardReady();
      const snap = this.getUIContext().getComponentSnapshot();
      /* 方式一：UIContext 组件截图（waitUntilRenderFinished 等渲染结束，弹层内比全局接口可靠） */
      let pixelMap: image.PixelMap | null = null;
      try {
        const result: image.PixelMap = await snap.get('shareCard', { waitUntilRenderFinished: true });
        if (result !== undefined && result !== null) {
          pixelMap = result;
        } else {
          console.error('ShareSheetPanel snapshot get returned undefined');
        }
      } catch (e) {
        console.error(`ShareSheetPanel snapshot get failed: ${JSON.stringify(e)}`);
      }
      /* 方式二：离屏构建卡片再截图（组件未挂树/弹层受限时的兜底） */
      if (pixelMap === null) {
        try {
          const data: ShareCardData = this.cardData;
          const result2: image.PixelMap = await snap.createFromBuilder(
            () => {
              this.cardPreview(data);
            },
            500,
            true,
            { waitUntilRenderFinished: true },
          );
          if (result2 !== undefined && result2 !== null) {
            pixelMap = result2;
          }
        } catch (e) {
          console.error(`ShareSheetPanel snapshot createFromBuilder failed: ${JSON.stringify(e)}`);
        }
      }
      if (pixelMap === null) {
        showToast($r('app.string.share_snapshot_failed'));
        return;
      }
      if (this.selectedFormat === ShareFormat.PDF) {
        /* PDF：长图 → 多页 A4 PDF 文件（PdfExporter 内部落盘 cacheDir），回调文件路径分享 */
        try {
          const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
          const pdfPath: string = await PdfExporter.export(context, pixelMap, this.shareTitle);
          this.onShare(this.selectedFormat, undefined, pdfPath);
        } catch (e) {
          console.error(`ShareSheetPanel pdf export failed: ${JSON.stringify(e)}`);
          showToast($r('app.string.share_snapshot_failed'));
        }
      } else {
        this.onShare(this.selectedFormat, pixelMap);
      }
    } else {
      this.onShare(this.selectedFormat);
    }
  }
}
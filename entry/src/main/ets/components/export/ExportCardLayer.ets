/**
 * 导出卡片隐藏层（宿主页面级，非弹层）
 *
 * 背景：bindSheet 弹层内的组件不在 componentSnapshot.get(id) 的查找范围
 * （实测报 100001 Invalid ID），createFromBuilder 离屏节点又不支持 Markdown
 * 三方组件 —— 弹层内截图两条路都不可行。本组件挂载在宿主页面根组件，
 * 用 position 移出屏幕的方式在正常组件树中渲染「分段聊天卡片」，
 * 供页面级 get(id) 逐段截图（页面级组件可正常截图）。
 *
 * 分段：每段 1 轮问答（1 条用户消息 + 其后所有 AI 回复）。单段高度受控，
 * 避免超长卡片一次截图超过渲染缓冲上限（约 16000px 物理像素）导致失败。
 * 截图时页面再按段高动态 scale 兜底（超限段缩小到安全高度，见宿主页面）。
 *
 * 使用流程：
 *  页面「点分享(PDF)」→ 置 showLayer=true → 本组件渲染隐藏分段卡片，
 *  等待全部段落 Markdown 渲染稳定 → onSegmentsReady(segCount, segHeights)
 *  回调通知页面 → 页面逐段 get('exportCard_0'...) 截图 → 生成 PDF
 */

import { image } from '@kit.ImageKit';
import { ShareCardItem, ShareCardData } from '../panel/ShareSheetPanel';
import { Markdown, MarkdownController } from "@luvi/lv-markdown-in";
import {
  SHARE_CARD_BG,
  SHARE_TEXT_PRIMARY,
  SHARE_USER_BUBBLE_BG,
  SHARE_AI_BUBBLE_BG,
} from '../../common/ShareStyle';

/* 卡片排版常量（vp，与 ShareSheetPanel 图片卡片保持一致，保证导出视觉统一） */

/** 导出卡片宽度（vp）：宿主页面按此换算拼接目标宽度（px） */
export const EXPORT_CARD_WIDTH: number = 340;
/** 分享格式轮数上限（问答轮数 = 用户消息条数）：图片 10 轮 / PDF 50 轮 */
export const EXPORT_IMAGE_MAX_ROUNDS: number = 10;
export const EXPORT_PDF_MAX_ROUNDS: number = 50;

const CARD_WIDTH: number = EXPORT_CARD_WIDTH;
const TITLE_FONT: number = 18;
const BODY_FONT: number = 16;
const USER_BUBBLE_MAX_WIDTH: number = 260;
const AI_BUBBLE_MAX_WIDTH: number = 300;
const BUBBLE_RADIUS: number = 16;

@ComponentV2
export struct ExportCardLayer {
  /* 是否渲染隐藏分段卡片（页面在导出时置 true，其余时间 false 不占资源） */
  @Param showLayer: boolean = false;
  /* 完整卡片数据（页面侧由消息列表组装） */
  @Param cardData: ShareCardData | null = null;
  /* 分享标题（首段卡片标题） */
  @Param shareTitle: string = "";
  /* 分享轮数上限（PDF=50 / 图片=10，由页面按格式传入） */
  @Param maxRounds: number = EXPORT_PDF_MAX_ROUNDS;
  /* 全部段落渲染稳定后回调：segCount 段数，segHeights 各段渲染高度（vp，供截图 scale 用） */
  @Event onSegmentsReady: (segCount: number, segHeights: number[]) => void = () => {};

  /* AI 消息 Markdown 渲染控制器（固定浅色主题，导出卡片白底与主题无关） */
  private mdController: MarkdownController = new MarkdownController();
  /* 各段渲染高度（vp，onAreaChange 记录；导出截图按此动态 scale） */
  @Local segHeights: number[] = [];
  /* 最近一次任一段落高度变化的时间戳：连续 500ms 无变化视为全部渲染稳定 */
  @Local lastChangeTime: number = 0;

  aboutToAppear(): void {
    /* 配置卡片内 Markdown 样式：固定浅色；关闭懒渲染确保截图时全部内容已渲染 */
    this.mdController
      .setLazyRender(false)
      .setCodeBlockTheme('light')
      .setMermaidTheme('light');
  }

  /* 监听 showLayer 置 true：启动「等渲染稳定 → 通知页面截图」流程 */
  @Monitor('showLayer')
  onShowLayerChanged(): void {
    if (this.showLayer && this.cardData !== null) {
      this.startExport();
    }
  }

  /**
   * 等全部段落渲染稳定后回调页面：先让出一帧（showLayer 生效、分段卡片挂载），
   * 再轮询 lastChangeTime 是否已连续 500ms 无变化（Markdown 异步渲染已落地）
   */
  private async startExport(): Promise<void> {
    await new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, 80);
    });
    const deadline: number = Date.now() + 15000; // 上限 15s（50 段 Markdown 渲染可能较久）
    while (Date.now() < deadline) {
      if (this.lastChangeTime > 0 && Date.now() - this.lastChangeTime > 500) {
        break;
      }
      await new Promise<void>((resolve: () => void) => {
        setTimeout(resolve, 50);
      });
    }
    const segCount: number = this.segments().length;
    this.onSegmentsReady(segCount, this.segHeights.slice());
  }

  /** 分段：limitItems 按轮数分组，每段 1 轮问答（1 条用户消息 + 其后 AI 回复） */
  private segments(): ShareCardItem[][] {
    const segs: ShareCardItem[][] = [];
    let seg: ShareCardItem[] = [];
    for (const item of this.limitItems()) {
      if (item.role === 'user' && seg.length > 0) {
        segs.push(seg);
        seg = [];
      }
      seg.push(item);
    }
    if (seg.length > 0) {
      segs.push(seg);
    }
    return segs;
  }

  /** 截取分享范围内消息：保留前 maxRounds 轮（用户消息计数，超出丢弃） */
  private limitItems(): ShareCardItem[] {
    const out: ShareCardItem[] = [];
    let userCount: number = 0;
    if (this.cardData === null) {
      return out;
    }
    for (const item of this.cardData.items) {
      if (item.role === 'user') {
        userCount++;
        if (userCount > this.maxRounds) {
          break;
        }
      }
      out.push(item);
    }
    return out;
  }

  build() {
    /* 仅在导出时渲染，position 移出屏幕外（组件仍在正常渲染树，Markdown 可正常渲染与截图） */
    if (this.showLayer && this.cardData !== null) {
      Column() {
        ForEach(this.segments(), (seg: ShareCardItem[], segIndex: number) => {
          Column() {
            /* 首段带卡片标题，后续段无标题（拼接时避免重复） */
            if (segIndex === 0) {
              Text(this.shareTitle)
                .fontSize(TITLE_FONT)
                .fontWeight(700)
                .fontColor(SHARE_TEXT_PRIMARY)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ bottom: 16 })
            }
            /* 段内气泡列表（用户右对齐 / AI 左对齐 Markdown 渲染） */
            ForEach(seg, (item: ShareCardItem) => {
              Row() {
                if (item.role === 'user') {
                  Blank()
                }
                Column() {
                  if (item.role === 'user') {
                    Text(item.content)
                      .fontSize(BODY_FONT)
                      .fontColor(SHARE_TEXT_PRIMARY)
                      .lineHeight(22)
                      .copyOption(CopyOptions.None)
                  } else {
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
                .backgroundColor(item.role === 'user' ? SHARE_USER_BUBBLE_BG : SHARE_AI_BUBBLE_BG)
                .constraintSize({ maxWidth: item.role === 'user' ? USER_BUBBLE_MAX_WIDTH : AI_BUBBLE_MAX_WIDTH })
                if (item.role === 'assistant') {
                  Blank()
                }
              }
              .width("100%")
              .alignItems(VerticalAlign.Top)
              .margin({ bottom: 14 })
            }, (item: ShareCardItem, idx: number) => `${item.role}_${idx}`)
          }
          .width("100%")
          .id(`exportCard_${segIndex}`) // 页面级 componentSnapshot 截图锚点
          .onAreaChange((oldValue: Area, newValue: Area) => {
            /* 记录本段高度与最近变化时间（渲染稳定检测依据） */
            const h: number = Number(newValue.height);
            if (h > 0) {
              const heights: number[] = this.segHeights.slice();
              heights[segIndex] = h;
              this.segHeights = heights;
              this.lastChangeTime = Date.now();
            }
          })
        }, (seg: ShareCardItem[], segIndex: number) => `seg_${segIndex}`)
      }
      .width(CARD_WIDTH)
      .position({ x: -20000, y: -20000 }) // 移出屏幕外，避免遮挡正常 UI
    }
  }
}

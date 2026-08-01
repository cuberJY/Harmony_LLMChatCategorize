/**
 * 底部聊天输入区域组件
 * 布局结构（从上到下）：
 *   1. 模型名称（小字、次要色）
 *   2. TextArea 输入框（最多 4 行，透明背景融入卡片）
 *   3. 底部操作栏：左侧切换按钮 + 右侧发送按钮
 *
 * 切换按钮（深度思考 / 联网搜索）：
 *   - 点击切换激活/默认态
 *   - 当前仅 UI 状态，后续接入 API 时传递参数
 */

import { COLORS, FONT_SIZES, SPACING } from "../common/AppConstants";
import { LengthMetrics } from "@kit.ArkUI";
@Component
export struct ChatInput {
  // 输入文本
  @State inputText: string = "";
  // 深度思考开关（后续传给 AIService 切换模型）
  @State deepThinking: boolean = false;
  // 联网搜索开关（后续传给 AIService 开启搜索）
  @State webSearch: boolean = false;

  // 输入框行高与行间距（用于精确计算最大高度）
  private inputLineHeight: number = 22; // 行高，需 >= FONT_SIZES.INPUT(15)
  private inputLineSpacing: number = 0; // 行间距
  @State inputMaxHeight: number = 0;

  aboutToAppear(): void {
    // 官方公式：高度 = 行高 × 行数 + 行间距 × (行数 - 1)
    this.inputMaxHeight = this.inputLineHeight * 5 + this.inputLineSpacing * 4;
  }

  // 模型名称（由父组件传入）
  modelName: string = "deepseek-chat";

  // 发送回调
  onChange?: (text: string, webSearch: boolean) => void;

  build() {
    Column() {
      // 1. 模型名称
      Text(this.modelName)
        .fontSize(FONT_SIZES.MODEL_NAME)
        .fontColor(COLORS.TEXT_SECONDARY)
        .width("100%")
        .margin({
          left: SPACING.SM,
          bottom: SPACING.XS,
        })

      // 2. 输入框
      TextArea({
        text: this.inputText,
        placeholder: "输入消息...",
      })
        .fontSize(FONT_SIZES.INPUT)
        .fontColor(COLORS.TEXT_PRIMARY)
        .width("100%")
        .lineHeight(this.inputLineHeight) // 显式行高
        .lineSpacing(LengthMetrics.px(this.inputLineSpacing)) // 行间距
        .constraintSize({ maxHeight: this.inputMaxHeight }) // 最大高度约束，触发滚动
        .placeholderColor(COLORS.TEXT_SECONDARY)
        .backgroundColor(COLORS.INPUT_BG)
        .borderWidth(0) // 去掉边框
        .padding({
          left: SPACING.XS,
          right: SPACING.XS,
          top: SPACING.XS,
          bottom: SPACING.XS,
        })
        .margin({
          top: SPACING.XS,
          bottom: SPACING.MD,
        })
        // 高度由 constraintSize(maxHeight) 约束，超出时滚动
        .onChange((value: string) => {
          this.inputText = value;
        })

      // 3. 底部操作栏
      Row() {
        // 左侧：切换按钮组
        Row() {
          // 深度思考
          Text("深度思考")
            .fontSize(FONT_SIZES.TOGGLE)
            .fontColor(this.deepThinking ? COLORS.TOGGLE_TEXT_ACTIVE : COLORS.TOGGLE_TEXT_INACTIVE)
            .padding({
              left: SPACING.SM,
              right: SPACING.SM,
              top: SPACING.SM,
              bottom: SPACING.SM,
            })
            .height(32)
            .borderRadius(16)
            .backgroundColor(
              this.deepThinking ? COLORS.TOGGLE_BG_ACTIVE : COLORS.TOGGLE_BG_INACTIVE,
            )
            .margin({ right: SPACING.SM })
            .onClick(() => {
              this.deepThinking = !this.deepThinking;
            })

          // 联网搜索
          Text("联网搜索")
            .fontSize(FONT_SIZES.TOGGLE)
            .fontColor(this.webSearch ? COLORS.TOGGLE_TEXT_ACTIVE : COLORS.TOGGLE_TEXT_INACTIVE)
            .padding({
              left: SPACING.SM,
              right: SPACING.SM,
              top: SPACING.XS,
              bottom: SPACING.XS,
            })
            .height(32)
            .borderRadius(16)
            .backgroundColor(this.webSearch ? COLORS.TOGGLE_BG_ACTIVE : COLORS.TOGGLE_BG_INACTIVE)
            .onClick(() => {
              this.webSearch = !this.webSearch;
            })
        }
        .layoutWeight(1) // 占据左侧空间，把发送按钮推到最右

        // 右侧：发送按钮
        Button() {
          SymbolGlyph($r("sys.symbol.arrowshape_up_fill"))
            .fontSize(18)
            .fontColor([Color.White])
        }
        .width(32)
        .height(32)
        .borderRadius(16) // 宽度一半 = 圆形
        .backgroundColor(
          this.inputText.trim().length > 0 ? COLORS.PRIMARY : COLORS.SEND_BTN_DISABLED,
        )
        .enabled(this.inputText.trim().length > 0) // 空内容时不可点击
        .onClick(() => {
          if (this.inputText.trim().length > 0 && this.onChange) {
            this.onChange(this.inputText.trim(), this.webSearch);
            this.inputText = ""; // 发送后清空
          }
        })
      }
      .width("100%")
      .alignItems(VerticalAlign.Center)
    }
    // 容器样式
    .width("100%")
    .padding({
      left: SPACING.MD,
      right: SPACING.MD,
      top: SPACING.SM,
      bottom: SPACING.SM,
    })
    .backgroundColor(COLORS.TITLE_BAR_BG) // 顶部边框
    .border({
      width: { top: 1 },
      color: { top: COLORS.DIVIDER },
    });
  }
}

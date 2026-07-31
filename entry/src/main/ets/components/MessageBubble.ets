/**
 * 聊天气泡组件
 * - 用户消息：右对齐，浅蓝背景
 * - AI 消息：左对齐，白色背景
 */
import { Message } from "../model/Message";
import { COLORS, FONT_SIZES, SPACING, BUBBLE } from "../common/AppConstants";
@Component
export struct MessageBubble {
  /**
   * @Prop 表示这个属性由父组件传入，当前组件不能修改
   * 当父组件的数据变化时，子组件会自动刷新
   * 这和 Qt 的 property binding 逻辑一致
   */
  @ObjectLink message: Message;
  @State isReasoningExpanded: boolean = true; // 是否展开思考内容

  build() {
    Row() {
      Column() {
        // 仅AI消息且有思考内容时显示
        if (!this.message.isUser() && this.message.reasoning.length > 0) {
          this.reasoningBlock();
        }
        // 正文气泡
        if (this.message.isUser()) {
          this.bubbleContent(COLORS.TEXT_USER, COLORS.BUBBLE_BG_USER);
        } else {
          this.bubbleContent(COLORS.TEXT_AI, COLORS.BUBBLE_BG_AI);
        }
      }
      .alignItems(HorizontalAlign.Start)
      .constraintSize({
        maxWidth: `${(this.message.isUser() ? BUBBLE.MAX_WIDTH_RATIO_USER : BUBBLE.MAX_WIDTH_RATIO_AI) * 100}%`,
      })
    }
    .width("100%")
    // 用户消息整行靠右，AI 消息整行靠左
    .justifyContent(this.message.isUser() ? FlexAlign.End : FlexAlign.Start)
    .padding({
      left: SPACING.MD,
      right: SPACING.MD,
      top: SPACING.SM,
      bottom: SPACING.SM,
    });
  }

  @Builder
  reasoningBlock() {
    Column() {
      // 标题行：点击可折叠/展开
      Row() {
        Text(
          this.message.isThinking
            ? "思考中…"
            : `已思考（用时 ${this.message.thinkingDuration} 秒）`,
        )
          .fontSize(FONT_SIZES.THINKING)
          .fontColor(COLORS.TEXT_SECONDARY)
          .margin({ left: SPACING.XS })
          .layoutWeight(1)
        // 折叠/展开箭头
        SymbolGlyph(
          this.isReasoningExpanded ? $r("sys.symbol.chevron_down") : $r("sys.symbol.chevron_right"),
        )
          .fontSize(FONT_SIZES.ICON_SM)
          .fontColor([COLORS.TEXT_SECONDARY])
          .margin({ right: SPACING.SM })
      }
      .onClick(() => {
        this.isReasoningExpanded = !this.isReasoningExpanded;
      })

      // 思考内容正文（展开时显示）
      if (this.isReasoningExpanded) {
        Row() {
          Text(this.message.reasoning)
            .constraintSize({ maxWidth: "95%" })
            .fontSize(FONT_SIZES.MODEL_NAME)
            .fontColor(COLORS.TEXT_SECONDARY)
            .margin({ top: SPACING.SM })
        }
        .width("100%")
        .justifyContent(FlexAlign.End);
      }
    }
    .width("100%")
    .alignItems(HorizontalAlign.Start)
    .padding({
      left: BUBBLE.PADDING_H,
      right: BUBBLE.PADDING_H,
      top: BUBBLE.PADDING_V,
      bottom: BUBBLE.PADDING_V,
    })
    .backgroundColor(COLORS.BUBBLE_BG_THINKING)
    .borderRadius(BUBBLE.RADIUS)
    .margin({
      bottom: SPACING.XS,
    });
  }

  @Builder
  bubbleContent(fontColor: string, bgColor: string) {
    // 用户消息 或 AI 已有正文：显示正文
    if (this.message.isUser() || this.message.content.length > 0) {
      Text(this.message.content)
        .fontSize(FONT_SIZES.BODY)
        .fontColor(fontColor)
        .padding({
          left: BUBBLE.PADDING_H,
          right: BUBBLE.PADDING_H,
          top: BUBBLE.PADDING_V,
          bottom: BUBBLE.PADDING_V,
        })
        .borderRadius(BUBBLE.RADIUS)
        .backgroundColor(bgColor)
        .constraintSize({
          maxWidth: `${(this.message.isUser() ? BUBBLE.MAX_WIDTH_RATIO_USER : BUBBLE.MAX_WIDTH_RATIO_AI) * 100}%`,
        });
    } else {
      // AI 消息、正文为空：显示阶段状态（优先级：搜索 > 失败 > 思考中）
      if (this.message.isSearching) {
        this.statusHint("正在搜索…");
      } else if (this.message.searchFailed) {
        this.statusHint("⚠️ 联网搜索失败，使用普通模式回答");
      } else if (this.message.isThinking && this.message.reasoning.length === 0) {
        this.statusHint("思考中…");
      }
      // 若 reasoning 非空（有推理内容），推理块标题本身会显示"思考中…"，这里留空避免重复
    }
  }

  @Builder
  statusHint(text: string) {
    Text(text)
      .fontSize(FONT_SIZES.BODY)
      .fontColor(COLORS.TEXT_SECONDARY)
      .padding({
        left: BUBBLE.PADDING_H,
        right: BUBBLE.PADDING_H,
        top: BUBBLE.PADDING_V,
        bottom: BUBBLE.PADDING_V,
      })
      .borderRadius(BUBBLE.RADIUS)
      .backgroundColor(COLORS.BUBBLE_BG_AI);
  }
}

/**
 * 聊天气泡组件（状态管理 V2）
 * - 用户消息：右对齐，浅蓝背景
 * - AI 消息：左对齐，白色背景
 */
import { Message } from "../../model/Message";
import { BUBBLE_MAX_WIDTH_RATIO_USER, BUBBLE_MAX_WIDTH_RATIO_AI } from "../../common/AppConstants";
@ComponentV2
export struct MessageBubble {
  /**
   * @Param：父组件传入的 @ObservedV2 消息对象
   * message 上的 @Trace 属性（content/reasoning/isThinking 等）变化时自动刷新本组件
   *（流式输出过程即依赖此机制实时重绘气泡）
   */
  @Param message: Message = new Message("", "user", "");
  @Local isReasoningExpanded: boolean = true; // 是否展开思考内容

  build() {
    Row() {
      Column() {
        // 仅AI消息且有思考内容时显示
        if (!this.message.isUser() && this.message.reasoning.length > 0) {
          this.reasoningBlock();
        }
        // 正文气泡
        if (this.message.isUser()) {
          this.bubbleContent($r('app.color.text_user'), $r('app.color.bubble_bg_user'));
        } else {
          this.bubbleContent($r('app.color.text_ai'), $r('app.color.bubble_bg_ai'));
        }
      }
      .alignItems(HorizontalAlign.Start)
      .constraintSize({
        maxWidth: `${(this.message.isUser() ? BUBBLE_MAX_WIDTH_RATIO_USER : BUBBLE_MAX_WIDTH_RATIO_AI) * 100}%`,
      })
    }
    .width("100%")
    // 用户消息整行靠右，AI 消息整行靠左
    .justifyContent(this.message.isUser() ? FlexAlign.End : FlexAlign.Start)
    .padding({
      left: $r('app.float.space_md'),
      right: $r('app.float.space_md'),
      top: $r('app.float.space_sm'),
      bottom: $r('app.float.space_sm'),
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
          .fontSize($r('app.float.font_thinking'))
          .fontColor($r('app.color.text_secondary'))
          .margin({ left: $r('app.float.space_xs') })
          .layoutWeight(1)
        // 折叠/展开箭头
        SymbolGlyph(
          this.isReasoningExpanded ? $r("sys.symbol.chevron_down") : $r("sys.symbol.chevron_right"),
        )
          .fontSize($r('app.float.font_icon_sm'))
          .fontColor([$r('app.color.text_secondary')])
          .margin({ right: $r('app.float.space_sm') })
      }
      .onClick(() => {
        this.isReasoningExpanded = !this.isReasoningExpanded;
      })

      // 思考内容正文（展开时显示）
      if (this.isReasoningExpanded) {
        Row() {
          Text(this.message.reasoning)
            .constraintSize({ maxWidth: "95%" })
            .fontSize($r('app.float.font_model_name'))
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: $r('app.float.space_sm') })
        }
        .width("100%")
        .justifyContent(FlexAlign.End);
      }
    }
    .width("100%")
    .alignItems(HorizontalAlign.Start)
    .padding({
      left: $r('app.float.bubble_padding_h'),
      right: $r('app.float.bubble_padding_h'),
      top: $r('app.float.bubble_padding_v'),
      bottom: $r('app.float.bubble_padding_v'),
    })
    .backgroundColor($r('app.color.bubble_bg_thinking'))
    .borderRadius($r('app.float.bubble_radius'))
    .margin({
      bottom: $r('app.float.space_xs'),
    });
  }

  @Builder
  bubbleContent(fontColor: ResourceColor, bgColor: ResourceColor) {
    // 用户消息 或 AI 已有正文：显示正文
    if (this.message.isUser() || this.message.content.length > 0) {
      Text(this.message.content)
        .fontSize($r('app.float.font_body'))
        .fontColor(fontColor)
        .padding({
          left: $r('app.float.bubble_padding_h'),
          right: $r('app.float.bubble_padding_h'),
          top: $r('app.float.bubble_padding_v'),
          bottom: $r('app.float.bubble_padding_v'),
        })
        .borderRadius($r('app.float.bubble_radius'))
        .backgroundColor(bgColor)
        .constraintSize({
          maxWidth: `${(this.message.isUser() ? BUBBLE_MAX_WIDTH_RATIO_USER : BUBBLE_MAX_WIDTH_RATIO_AI) * 100}%`,
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
      .fontSize($r('app.float.font_body'))
      .fontColor($r('app.color.text_secondary'))
      .padding({
        left: $r('app.float.bubble_padding_h'),
        right: $r('app.float.bubble_padding_h'),
        top: $r('app.float.bubble_padding_v'),
        bottom: $r('app.float.bubble_padding_v'),
      })
      .borderRadius($r('app.float.bubble_radius'))
      .backgroundColor($r('app.color.bubble_bg_ai'));
  }
}

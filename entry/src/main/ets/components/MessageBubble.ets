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

  build() {
    // Row 作为气泡的外层容器，控制左右对齐
    Row() {
      // 用户消息：气泡在右侧
      if (this.message.isUser()) {
        this.bubbleContent(COLORS.TEXT_USER, COLORS.BUBBLE_BG_USER);
      } else {
        this.bubbleContent(COLORS.TEXT_AI, COLORS.BUBBLE_BG_AI);
      }
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
  bubbleContent(fontColor: string, bgColor: string) {
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
      .constraintSize({ maxWidth: `${BUBBLE.MAX_WIDTH_RATIO * 100}%` });
  }
}

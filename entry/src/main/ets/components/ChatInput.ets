/**
 * 底部聊天输入区域组件
 * 固定在页面底部
 * TextArea 自动扩展（最多显示 4 行）
 * "发送"按钮：有内容时点亮，无内容时灰色禁用
 * 点击发送后通过回调通知父组件（ChatPage）
 */

import { COLORS, FONT_SIZES, SPACING } from "../common/AppConstants";
@Component
export struct ChatInput {
  /**
   * @State 是组件内部私有状态，由组件自己管理
   * 用户每输入一个字符，这个值都会更新
   */
  @State inputText: string = "";

  /**
   * 回调函数：当用户点击"发送"时触发
   * 父组件（ChatPage）通过此回调拿到用户输入的文字
   * 这和 Qt 中 emit signal / 设置 callback 思路一样
   */
  onChange?: (text: string) => void;

  build() {
    Row() {
      // 文本输入框
      TextArea({
        text: this.inputText,
        placeholder: "输入消息...",
      })
        .fontSize(FONT_SIZES.INPUT)
        .fontColor(COLORS.TEXT_PRIMARY)
        .placeholderColor(COLORS.TEXT_SECONDARY)
        .backgroundColor(COLORS.INPUT_BG)
        .borderRadius(20)
        // 胶囊形圆角
        .borderWidth(1)
        .borderColor(COLORS.INPUT_BORDER)
        .padding({
          left: SPACING.MD,
          right: SPACING.MD,
          top: SPACING.SM,
          bottom: SPACING.SM,
        })
        .maxLines(4)
        // maxLines(4)：最多显示 4 行，超出后可滚动
        .layoutWeight(1)
        // 占据剩余宽度（Row 布局中放在 Button 左边）
        .onChange((value: string) => {
          this.inputText = value;
        })

      // 发送按钮
      Button() {
        SymbolGlyph($r("sys.symbol.arrowshape_right_fill"))
          .fontSize(20)
          .fontColor([Color.White])
      }
      .width(36)
      .height(36)
      .borderRadius(18)
      // 正方形 + borderRadius = 宽度一半 = 完美圆形
      .backgroundColor(this.inputText.trim().length > 0 ? COLORS.PRIMARY : COLORS.SEND_BTN_DISABLED)
      .margin({ left: SPACING.SM })
      .enabled(this.inputText.trim().length > 0)
      // 空内容时按钮不可点击
      .onClick(() => {
        // 点击发送 → 通过回调把文字传给父组件
        if (this.inputText.trim().length > 0 && this.onChange) {
          this.onChange(this.inputText.trim());
          // 发送后清空输入框
          this.inputText = "";
        }
      })
    }
    .width("100%")
    .padding({
      left: SPACING.MD,
      right: SPACING.MD,
      top: SPACING.SM,
      bottom: SPACING.SM,
    })
    .backgroundColor(COLORS.TITLE_BAR_BG)
    // 输入区背景色
    // 顶部分割线
    .border({
      width: { top: 1 },
      color: { top: COLORS.DIVIDER },
    });
  }
}

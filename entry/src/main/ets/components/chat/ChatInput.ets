/**
 * 底部聊天输入区域组件（状态管理 V2）
 * 布局结构（从上到下）：
 *   1. 模型名称（小字、次要色）
 *   2. TextArea 输入框（最多 4 行，透明背景融入卡片）
 *   3. 底部操作栏：左侧切换按钮 + 右侧发送按钮
 *
 * 切换按钮（深度思考 / 联网搜索）：
 *   - 点击切换激活/默认态
 *   - 当前仅 UI 状态，后续接入 API 时传递参数
 *
 * V2 说明：@Local 为组件内部状态（输入文本/开关/最大高度），
 * @Param 为父组件传入的只读参数（模型名称），回调用普通成员承载
 */

import { LengthMetrics } from "@kit.ArkUI";
@ComponentV2
export struct ChatInput {
  // 输入文本
  @Local inputText: string = "";
  // 深度思考开关（后续传给 LLM Provider 切换模型）
  @Local deepThinking: boolean = true;
  // 联网搜索开关（后续传给 LLM Provider 开启搜索）
  @Local webSearch: boolean = true;

  // 输入框行高与行间距（用于精确计算最大高度）
  private inputLineHeight: number = 22; // 行高，需 >= 输入字号（15fp）
  private inputLineSpacing: number = 0; // 行间距
  @Local inputMaxHeight: number = 0;

  aboutToAppear(): void {
    // 官方公式：高度 = 行高 × 行数 + 行间距 × (行数 - 1)
    this.inputMaxHeight = this.inputLineHeight * 5 + this.inputLineSpacing * 4;
  }

  // 模型名称（由父组件传入）
  @Param modelName: string = "";
  // 编辑态预填文本（点击用户消息「编辑」后回填到输入框；非空即触发回填）
  @Param prefillText: string = "";
  // 是否处于编辑态（编辑消息中，显示提示文案）
  @Param isEditing: boolean = false;

  // 监听 prefillText 变化：回填内容到输入框（@Monitor 是 V2 监听 @Param 变化的机制）
  @Monitor('prefillText')
  onPrefillChanged(): void {
    if (this.prefillText.length > 0) {
      this.inputText = this.prefillText;
    }
  }

  // 发送回调（@Event：V2 允许父组件初始化的普通事件）
  @Event onChange: (text: string, webSearch: boolean, deepThinking: boolean) => void = (text: string, webSearch: boolean, deepThinking: boolean) => {};

  build() {
    Column() {
      // 1. 模型名称 / 编辑提示（编辑态时优先显示编辑提示）
      Text(
        this.isEditing
          ? $r('app.string.edit_mode_hint')
          : (this.modelName.length > 0 ? this.modelName : "未配置模型，请前往设置"),
      )
        .fontSize($r('app.float.font_model_name'))
        .fontColor($r('app.color.text_secondary'))
        .width("100%")
        .margin({
          left: $r('app.float.space_sm'),
          bottom: $r('app.float.space_xs'),
        })

      // 2. 输入框
      TextArea({
        text: this.inputText,
        placeholder: "输入消息...",
      })
        .fontSize($r('app.float.font_input'))
        .fontColor($r('app.color.text_primary'))
        .width("100%")
        .lineHeight(this.inputLineHeight) // 显式行高
        .lineSpacing(LengthMetrics.px(this.inputLineSpacing)) // 行间距
        .constraintSize({ maxHeight: this.inputMaxHeight }) // 最大高度约束，触发滚动
        .placeholderColor($r('app.color.text_secondary'))
        .backgroundColor($r('app.color.input_bg'))
        .borderWidth(0) // 去掉边框
        .padding({
          left: $r('app.float.space_xs'),
          right: $r('app.float.space_xs'),
          top: $r('app.float.space_xs'),
          bottom: $r('app.float.space_md'),
        })
        .margin({
          top: $r('app.float.space_xs'),
          bottom: $r('app.float.space_md'),
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
            .fontSize($r('app.float.font_toggle'))
            .fontColor(this.deepThinking ? $r('app.color.toggle_text_active') : $r('app.color.toggle_text_inactive'))
            .padding({
              left: $r('app.float.space_sm'),
              right: $r('app.float.space_sm'),
              top: $r('app.float.space_xs'),
              bottom: $r('app.float.space_xs'),
            })
            .height(32)
            .borderRadius(16)
            .backgroundColor(
              this.deepThinking ? $r('app.color.toggle_bg_active') : $r('app.color.toggle_bg_inactive'),
            )
            .margin({ right: $r('app.float.space_sm') })
            .onClick(() => {
              this.deepThinking = !this.deepThinking;
            })

          // 联网搜索
          Text("联网搜索")
            .fontSize($r('app.float.font_toggle'))
            .fontColor(this.webSearch ? $r('app.color.toggle_text_active') : $r('app.color.toggle_text_inactive'))
            .padding({
              left: $r('app.float.space_sm'),
              right: $r('app.float.space_sm'),
              top: $r('app.float.space_xs'),
              bottom: $r('app.float.space_xs'),
            })
            .height(32)
            .borderRadius(16)
            .backgroundColor(this.webSearch ? $r('app.color.toggle_bg_active') : $r('app.color.toggle_bg_inactive'))
            .onClick(() => {
              this.webSearch = !this.webSearch;
            })
        }
        .layoutWeight(1) // 占据左侧空间，把发送按钮推到最右

        // 右侧：发送按钮
        Button() {
          SymbolGlyph($r("sys.symbol.arrowshape_up_fill"))
            .fontSize($r('app.float.font_icon_xl'))
            .fontColor([Color.White])
            .margin({ bottom: 1 })
        }
        .width(32)
        .height(32)
        .type(ButtonType.Circle)
        .backgroundColor(
          this.inputText.trim().length > 0 ? $r('app.color.primary') : $r('app.color.send_btn_disabled'),
        )
        .enabled(this.inputText.trim().length > 0) // 空内容时不可点击
        .onClick(() => {
          if (this.inputText.trim().length > 0 && this.onChange) {
            this.onChange(this.inputText.trim(), this.webSearch, this.deepThinking);
            this.inputText = ""; // 发送后清空输入框
          }
        })
      }
      .width("100%")
      .alignItems(VerticalAlign.Center)
    }
    // 容器样式
    .width("100%")
    .padding({
      left: $r('app.float.space_md'),
      right: $r('app.float.space_md'),
      top: $r('app.float.space_sm'),
      bottom: $r('app.float.space_sm'),
    })
    .backgroundColor($r('app.color.title_bar_bg')) // 顶部边框
    .border({
      width: { top: 1 },
      color: { top: $r('app.color.divider') },
    });
  }
}

/**
 * 底部聊天输入区域组件（状态管理 V2）
 * 布局结构（从上到下）：
 *   1. 模型名称（小字、次要色）
 *   2. TextArea 输入框（最多 4 行，透明背景融入卡片）
 *   3. 底部操作栏：左侧切换按钮 + 右侧发送按钮
 *
 * 切换按钮（深度思考 / 联网搜索）：
 *   - 状态由父级 ViewModel 持有（@Param 单向传入），点击后经 onToggleChange 上报，
 *     由 VM 更新唯一真源并回流刷新 → 发送 / 重新生成 / 新建分支使用同一份当前开关
 *   - 发送时通过 onChange 上报文本（开关值由 VM 直接读取，不再重复传递）
 *
 * V2 说明：@Local 为组件内部状态（输入文本/最大高度），
 * @Param 为父组件传入的参数（模型名称/开关状态/编辑态），回调用 @Event 承载
 */

import { LengthMetrics } from "@kit.ArkUI";
import { inputMethod } from "@kit.IMEKit";

@ComponentV2
export struct ChatInput {
  @Local inputText: string = "";
  /* 输入框行高与行间距（用于精确计算最大高度） */
  private inputLineHeight: number = 22; // 行高，需 >= 输入字号（15fp）
  private inputLineSpacing: number = 0; // 行间距
  @Local inputMaxHeight: number = 0;

  aboutToAppear(): void {
    /* 官方公式：高度 = 行高 × 行数 + 行间距 × (行数 - 1) */
    this.inputMaxHeight = this.inputLineHeight * 5 + this.inputLineSpacing * 4;
    /* 修复：@Monitor 不触发初始值——挂载时若已带编辑预填需主动回填 */
    if (this.prefillText.length > 0) {
      this.inputText = this.prefillText;
    }
  }

  /* 发送/暂停按钮是否可用：生成中恒可用（暂停键）；否则输入框有内容才可点（发送键） */
  private isSendButtonEnabled(): boolean {
    return this.streamState === "streaming" || this.inputText.trim().length > 0;
  }

  /* 模型名称（由父组件传入） */
  @Param modelName: string = "";
  /* 编辑态预填文本（点击用户消息「编辑」后回填到输入框；非空即触发回填） */
  @Param prefillText: string = "";
  /* 是否处于编辑态（编辑消息中，显示提示文案） */
  @Param isEditing: boolean = false;
  /* 深度思考开关（由 ViewModel 传入，唯一真源） */
  @Param deepThinking: boolean = true;
  /* 联网搜索开关（由 ViewModel 传入，唯一真源） */
  @Param webSearch: boolean = true;
  /**
   * 流式生成状态（由 ViewModel 传入，唯一真源）：
   * idle=发送键 / streaming=暂停键 / paused=显示「继续生成」按钮
   */
  @Param streamState: "idle" | "streaming" | "paused" = "idle";

  /* 监听 prefillText 变化：回填内容到输入框（@Monitor 是 V2 监听 @Param 变化的机制） */
  @Monitor('prefillText')
  onPrefillChanged(): void {
    if (this.prefillText.length > 0) {
      this.inputText = this.prefillText;
      /* 编辑回填后自动弹出输入法：先清焦点再请求焦点（确保已聚焦时也能重新弹起键盘） */
      const focus = this.getUIContext().getFocusController();
      focus.clearFocus();
      setTimeout(() => {
        focus.requestFocus('chat_input');
      }, 0);
    } else {
      /* 编辑态取消/新建对话（prefillText 被清空）→ 同步清空输入框 */
      this.inputText = "";
    }
  }

  /* 开关切换回调（@Event：点击切换按钮时上报新状态，由父级更新 VM 唯一真源） */
  @Event onToggleChange: (webSearch: boolean, deepThinking: boolean) => void = (webSearch: boolean, deepThinking: boolean) => {};
  /* 发送回调（@Event：仅上报文本，开关状态由父级 VM 读取） */
  @Event onChange: (text: string) => void = (text: string) => {};
  /* 暂停生成回调（生成中点击暂停键时触发，由 VM 中止流式请求） */
  @Event onPause: () => void = () => {};
  /* 取消编辑回调（编辑态点击顶部右侧 xmark 时触发，由 VM 退出编辑态并清空输入框） */
  @Event onCancelEdit: () => void = () => {};
  /* 输入框焦点变化回调（@Event：聚焦=键盘将弹出，失焦=可能收起；父级据此驱动全局键盘标志） */
  @Event onInputFocusChange: (hasFocus: boolean) => void = (hasFocus: boolean) => {};

  build() {
    Column() {
      /* 1. 顶部信息行：左侧模型名称/编辑提示，右侧「取消编辑」按钮（仅编辑态显示） */
      Row() {
        Text(
          this.isEditing
            ? $r('app.string.edit_mode_hint')
            : (this.modelName.length > 0 ? this.modelName : "未配置模型，请前往设置"),
        )
          .fontSize($r('app.float.font_model_name'))
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1) // 占据剩余空间，把取消按钮推到最右
          .margin({ left: $r('app.float.space_xs') })

        /* 编辑态：右侧 xmark 取消编辑（清空输入框并退出编辑态） */
        if (this.isEditing) {
          Button() {
            SymbolGlyph($r("sys.symbol.xmark"))
              .fontSize($r('app.float.font_icon_lg'))
              .fontWeight(700)
              .fontColor([$r('app.color.text_primary')])
          }
          .width(26)
          .height(26)
          .type(ButtonType.Circle)
          .backgroundColor($r('app.color.toggle_bg_inactive'))
          .padding({
            left: $r('app.float.space_xs'),
            right: $r('app.float.space_xs'),
            top: $r('app.float.space_xs'),
            bottom: $r('app.float.space_xs'),
          })
          .margin({ right: $r('app.float.space_xs') })
          .onClick(() => {
            /* 取消编辑：先收起输入法键盘，再上报退出编辑态（VM 清空 prefillText → @Monitor 联动清空输入框） */
            inputMethod.getController().stopInput();
            this.onCancelEdit();
          })
        }
      }
      .width("100%")
      .margin({
        bottom: $r('app.float.space_xs'),
      })

      /* 2. 输入框 */
      TextArea({
        text: this.inputText,
        placeholder: "输入消息...",
      })
        .id('chat_input') // 供自动弹出输入法时请求焦点
        /**
         * TextArea 默认 stopBackPress(true)，会拦截返回键、不触发 NavDestination.onBackPressed，
         * 导致键盘收起后第二次返回键被 TextArea 消费并冒泡到 UIAbility 直接退出应用。
         * 置 false 让返回键正常传到 onBackPressed，由页面按「收键盘 > 取消编辑 > 退出」优先级处理。
         */
        .stopBackPress(false)
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
        /* 高度由 constraintSize(maxHeight) 约束，超出时滚动 */
        .onChange((value: string) => {
          this.inputText = value;
        })
        /**
         * 聚焦 → 键盘必然弹出（TextArea 默认 enableKeyboardOnFocus(true)）；失焦 → 可能收起。
         * 上报父级驱动全局键盘标志：该信号是同步可靠的，弥补 keyboardHeightChange
         * 「冷启动首次弹键盘事件丢失 / 键盘避让 NONE 模式下不派发」的被动事件缺陷
         */
        .onFocus(() => {
          this.onInputFocusChange(true);
        })
        .onBlur(() => {
          this.onInputFocusChange(false);
        })

      /* 3. 底部操作栏 */
      Row() {
        /* 左侧：切换按钮组 */
        Row() {
          /* 深度思考 */
          Text("深度思考")
            .fontSize($r('app.float.font_toggle'))
            .fontColor(
              this.deepThinking ? $r('app.color.toggle_text_active') : $r('app.color.toggle_text_inactive')
            )
            .padding({
              left: $r('app.float.space_sm'),
              right: $r('app.float.space_sm'),
              top: $r('app.float.space_xs'),
              bottom: $r('app.float.space_xs'),
            })
            .height(32)
            .borderRadius(16)
            .backgroundColor(
              this.deepThinking ? $r('app.color.toggle_bg_active') : $r('app.color.toggle_bg_inactive')
            )
            .margin({ right: $r('app.float.space_sm') })
            .onClick(() => {
              /* 上报新状态给父级（VM 更新唯一真源后回流刷新本组件） */
              this.onToggleChange(this.webSearch, !this.deepThinking);
            })

          /* 联网搜索 */
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
              /* 上报新状态给父级（VM 更新唯一真源后回流刷新本组件） */
              this.onToggleChange(!this.webSearch, this.deepThinking);
            })
        }
        .layoutWeight(1) // 占据左侧空间，把发送按钮推到最右

        /* 右侧：发送 / 暂停按钮（生成中显示暂停键，点击暂停；普通态显示发送键） */
        Button() {
          SymbolGlyph(
            this.streamState === "streaming"
              ? $r("sys.symbol.square_fill") // 生成中 → 暂停图标（实心方块）
              : $r("sys.symbol.arrowshape_up_fill"), // 普通态 → 发送图标
          )
            .fontSize(
              this.streamState === "streaming"
                ? $r('app.float.font_icon_md')
                : $r('app.float.font_icon_xl')
            )
            .fontColor([Color.White])
            .margin({ bottom: 1 })
        }
        .width(32)
        .height(32)
        .type(ButtonType.Circle)
        .backgroundColor(
          this.isSendButtonEnabled() ? $r('app.color.primary') : $r('app.color.send_btn_disabled'),
        )
        .enabled(this.isSendButtonEnabled()) // 生成中恒可点（暂停键）；否则有内容才可点（发送键）
        .onClick(() => {
          if (this.streamState === "streaming") {
            /* 生成中：暂停（中止流式请求，保留已生成内容） */
            this.onPause();
          } else if (this.inputText.trim().length > 0 && this.onChange) {
            /* 普通态：发送（开关状态由父级 VM 读取（唯一真源），这里仅上报文本） */
            inputMethod.getController().stopInput(); // 发送后自动收起输入法键盘
            this.onChange(this.inputText.trim());
            this.inputText = ""; // 发送后清空输入框
          }
        })
      }
      .width("100%")
      .alignItems(VerticalAlign.Center)
    }
    /* 容器样式 */
    .width("100%")
    .padding({
      left: $r('app.float.space_md'),
      right: $r('app.float.space_md'),
      top: $r('app.float.space_sm'),
      bottom: $r('app.float.space_sm'),
    })
    .backgroundColor($r('app.color.input_bg'))
    .border({
      width: { top: 2 },
      color: { top: $r('app.color.divider') },
    });
  }
}

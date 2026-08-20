/**
 * 底部聊天输入区域组件（状态管理 V2）
 * 布局结构（从上到下）：
 *   1. 模型名称（小字、次要色）
 *   2. TextArea 输入框（最多 4 行，透明背景融入卡片）
 *   3. 底部操作栏：左侧切换按钮 + 右侧发送按钮
 *
 * 切换按钮（思考强度 / 联网搜索）：
 *   - 状态由父级 ViewModel 持有（@Param 单向传入），点击后经 onThinkingChange / onWebSearchChange 上报，
 *     由 VM 更新唯一真源并回流刷新 → 发送 / 重新生成 / 新建分支使用同一份当前设置
 *   - 思考强度为多档位选择（关闭/轻量/深度/极限），点击按钮弹出下拉菜单（bindMenu，样式同设置页模型选择）；
 *     联网搜索为开/关切换
 *   - 发送时通过 onChange 上报文本（开关值由 VM 直接读取，不再重复传递）
 *
 * V2 说明：@Local 为组件内部状态（输入文本/最大高度），
 * @Param 为父组件传入的参数（模型名称/开关状态/编辑态），回调用 @Event 承载
 */

import { LengthMetrics } from "@kit.ArkUI";
import { inputMethod } from "@kit.IMEKit";
import { ThinkingEffort, ThinkingLevel, THINKING_LEVELS, thinkingLevelLabel, DEFAULT_THINKING_EFFORT } from "../../config/ModelPresets";

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
  /* 思考强度（由 ViewModel 传入，唯一真源；none 关闭 / low 轻量 / high 深度 / max 极限） */
  @Param thinkingEffort: ThinkingEffort = DEFAULT_THINKING_EFFORT;
  /* 联网搜索开关（由 ViewModel 传入，唯一真源） */
  @Param webSearch: boolean = true;
  /**
   * 流式生成状态（由 ViewModel 传入，唯一真源）：
   * idle=发送键 / streaming=暂停键 / paused=显示「继续生成」按钮
   */
  @Param streamState: "idle" | "streaming" | "paused" = "idle";
  /* 底部导航条高度（vp，父级传入）：输入区内容用其手动避让，避免被导航条遮挡 */
  @Param navBarHeightVp: number = 0;

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

  /* 联网搜索开关切换回调（@Event：点击切换按钮时上报新状态，由父级更新 VM 唯一真源） */
  @Event onWebSearchChange: (webSearch: boolean) => void = (webSearch: boolean) => {};
  /* 思考强度档位选择回调（@Event：底部面板点选时上报新档位，由父级更新 VM 唯一真源） */
  @Event onThinkingChange: (effort: ThinkingEffort) => void = (effort: ThinkingEffort) => {};
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
            ? "正在编辑消息（发送后在该位置创建新分支）"
            : (this.modelName.length > 0 ? this.modelName : "未配置模型，请前往设置"),
        )
          .fontSize($r('app.float.font_model_name'))
          .fontColor($r('app.color.font_secondary'))
          .layoutWeight(1) // 占据剩余空间，把取消按钮推到最右
          .margin({ left: $r('app.float.space_xs') })

        /* 编辑态：右侧 xmark 取消编辑（清空输入框并退出编辑态） */
        if (this.isEditing) {
          Button() {
            SymbolGlyph($r("sys.symbol.xmark"))
              .fontSize($r('app.float.font_icon_lg'))
              .fontWeight(700)
              .fontColor([$r('app.color.font_primary')])
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
        .fontColor($r('app.color.font_primary'))
        .width("100%")
        .lineHeight(this.inputLineHeight) // 显式行高
        .lineSpacing(LengthMetrics.px(this.inputLineSpacing)) // 行间距
        .constraintSize({ maxHeight: this.inputMaxHeight }) // 最大高度约束，触发滚动
        .placeholderColor($r('app.color.font_secondary'))
        .backgroundColor($r('app.color.chat_input_bg'))
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
          /* 思考强度：按钮文字显示当前档位；点击弹出下拉菜单选择（非 none 时高亮，表示思考已开启） */
          Row() {
            SymbolGlyph($r("sys.symbol.AI_deep_thinking"))
              .fontSize($r('app.float.font_icon_lg'))
              .fontWeight(600)
              .fontColor(
                this.thinkingEffort !== "none"
                  ? [$r('app.color.toggle_text_active')]
                  : [$r('app.color.toggle_text_inactive')]
              )
              .margin({
                left: $r('app.float.space_xxs'),
                right: $r('app.float.space_xs')
              })
            Text(thinkingLevelLabel(this.thinkingEffort))
              .width(35)
              .fontSize($r('app.float.font_toggle'))
              .fontColor(
                this.thinkingEffort !== "none"
                  ? $r('app.color.toggle_text_active')
                  : $r('app.color.toggle_text_inactive')
              )
            SymbolGlyph($r("sys.symbol.chevron_down"))
              .fontSize($r('app.float.font_icon_md'))
              .fontWeight(600)
              .fontColor(
                this.thinkingEffort !== "none"
                  ? [$r('app.color.toggle_text_active')]
                  : [$r('app.color.toggle_text_inactive')]
              )
          }
          .padding({
            left: $r('app.float.space_sm'),
            right: $r('app.float.space_sm'),
            top: $r('app.float.space_xs'),
            bottom: $r('app.float.space_xs'),
          })
          .height(32)
          .borderRadius(16)
          .backgroundColor(
            this.thinkingEffort !== "none"
              ? $r('app.color.toggle_bg_active')
              : $r('app.color.toggle_bg_inactive')
          )
          .margin({ right: $r('app.float.space_sm') })
          /* 下拉菜单选择（bindMenu） */
          .bindMenu(this.thinkingMenuBuilder())

          /* 联网搜索 */
          Row() {
            SymbolGlyph($r("sys.symbol.pc_ic_tab_index"))
              .fontSize($r('app.float.font_icon_lg'))
              .fontWeight(600)
              .fontColor(
                this.webSearch
                  ? [$r('app.color.toggle_text_active')]
                  : [$r('app.color.toggle_text_inactive')]
              )
              .margin({
                right: $r('app.float.space_xxs')
              })
            Text("联网搜索")
              .fontSize($r('app.float.font_toggle'))
              .fontColor(
                this.webSearch
                  ? $r('app.color.toggle_text_active')
                  : $r('app.color.toggle_text_inactive')
              )
          }
          .padding({
                left: $r('app.float.space_sm'),
                right: $r('app.float.space_sm'),
                top: $r('app.float.space_xs'),
                bottom: $r('app.float.space_xs'),
              })
          .height(32)
          .borderRadius(16)
          .backgroundColor(
            this.webSearch
              ? $r('app.color.toggle_bg_active')
              : $r('app.color.toggle_bg_inactive')
            )
          .onClick(() => {
            /* 上报新状态给父级（VM 更新唯一真源后回流刷新本组件） */
            this.onWebSearchChange(!this.webSearch);
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
          this.isSendButtonEnabled() ? $r('app.color.brand') : $r('app.color.send_btn_disabled'),
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
      .margin({ bottom: $r('app.float.space_xl') })
    }
    /* 容器样式 */
    .width("100%")
    /**
     * 沉浸式：expandSafeArea 让白色背景向下延伸到底部导航条背后；
     * 内容用显式 padding（导航条高度）避让手势条——safeAreaPadding 在固定高度组件上会失效
     */
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .padding({
      left: $r('app.float.space_md'),
      right: $r('app.float.space_md'),
      top: $r('app.float.space_sm'),
      bottom: this.navBarHeightVp + 4, // 4 = space_xs，底部额外留出手势条空间
    })
    .backgroundColor($r('app.color.chat_input_bg'))
    .border({
      width: { top: 2 },
      color: { top: $r('app.color.divider') },
    })
  }

  /**
   * 思考强度下拉菜单（bindMenu 内容，样式同设置页 Select 模型选择）
   * 列出全部档位（关闭/轻量/深度/极限）
   * 选中某一项 → 上报父级 VM 更新唯一真源，菜单自动关闭。
   * 选中态由 @Param thinkingEffort（父级回流）驱动，菜单收起后按钮文字同步更新
   */
  @Builder
  thinkingMenuBuilder() {
    Menu() {
      ForEach(
        THINKING_LEVELS,
        (level: ThinkingLevel) => {
          MenuItem({ content: level.label })
            /* 选中档位背景高亮（与思考强度按钮高亮同色），未选中保持透明露出菜单底色 */
            .backgroundColor(
              this.thinkingEffort === level.value
                ? $r('app.color.toggle_bg_active')
                : Color.Transparent
            )
            .contentFontColor(
              this.thinkingEffort === level.value
                ? $r('app.color.toggle_text_active')
                : $r('app.color.font_primary')
            )
            .onChange(() => {
              /* 点选档位 → 上报父级（VM 更新唯一真源后回流刷新按钮文字与菜单选中态） */
              this.onThinkingChange(level.value);
            })
        },
        (level: ThinkingLevel) => level.value,
      )
    }
  }
}

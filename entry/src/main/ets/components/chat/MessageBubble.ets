/**
 * 聊天气泡组件（状态管理 V2）
 * - 用户消息：右对齐，浅蓝背景
 * - AI 消息：左对齐，白色背景
 */
import { Message } from "../../model/Message";
import { BUBBLE_MAX_WIDTH_RATIO_USER, BUBBLE_MAX_WIDTH_RATIO_AI } from "../../common/AppConstants";
import { Markdown, MarkdownController } from "@luvi/lv-markdown-in";
import { common, ConfigurationConstant, EnvironmentCallback } from '@kit.AbilityKit';
@ComponentV2
export struct MessageBubble {
  /**
   * @Param：父组件传入的 @ObservedV2 消息对象
   * message 上的 @Trace 属性（content/reasoning/isThinking/isStreaming 等）变化时自动刷新本组件
   *（流式输出过程即依赖此机制实时重绘气泡）
   */
  @Param message: Message = new Message("", "user", "");
  @Local isReasoningExpanded: boolean = true; // 是否展开思考内容
  @Local isDarkMode: boolean = false; // 跟随系统深浅色（驱动代码块/思维导图主题切换）
  // lv-markdown-in 的样式/拦截控制器（普通成员即可，无需响应式）
  private mdController: MarkdownController = new MarkdownController();
  private envCallbackId: number = -1; // 系统环境监听回调 ID（aboutToDisappear 注销用）

  aboutToAppear(): void {
    // 依据当前系统颜色模式配置 Markdown 颜色与代码块/思维导图主题
    this.applyMarkdownTheme();
    // 注册系统环境监听（深浅色切换时动态更新代码块/思维导图主题）
    this.registerEnvironmentListener();
  }

  aboutToDisappear(): void {
    this.unregisterEnvironmentListener();
  }

  /**
   * 深色模式适配（lv-markdown-in）：
   *  - 字体类颜色传 $r() 资源引用，系统自动在深浅色切换时加载 dark/ 目录对应色值（无需代码干预）
   *  - 代码块/思维导图主题只能传字符串 'light'/'dark'，必须监听系统 colorMode 手动切换
   *  - LaTeX 公式颜色只能传十六进制 number（公式渲染为 pixelMap 位图，库不支持 $r 引用），同样手动切换
   */
  private applyMarkdownTheme(): void {
    const host = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    let isDark = this.isDarkMode;
    if (host !== undefined && host.config !== undefined) {
      isDark = host.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    }
    this.isDarkMode = isDark;
    this.applyMarkdownColors(isDark);
  }

  private applyMarkdownColors(isDark: boolean): void {
    // 链式部分（返回 this 的 setter）
    const controller = this.mdController
      .setTitleColor($r('app.color.text_primary'))
      .setTextColor($r('app.color.text_ai'))
      .setInlineCodeColor($r('app.color.text_important'))
      .setInlineCodeBackgroundColor($r('app.color.bubble_bg_thinking'))
      .setQuoteTextColor($r('app.color.text_secondary'))
      .setQuoteBorderColor($r('app.color.divider'))
      .setQuoteBackgroundColor($r('app.color.bubble_bg_thinking'))
      .setHyperlinkTextColor($r('app.color.text_important'))
      .setHyperlinkBackgroundColor(Color.Transparent)
      .setTableTitleTextColor($r('app.color.text_primary'))
      .setTableTitleBackgroundColor($r('app.color.bubble_bg_thinking'))
      .setTableBackgroundColor($r('app.color.bubble_bg_ai'))
      .setTableInterleaveBackgroundColor($r('app.color.bubble_bg_thinking'))
      .setTableOuterBorderColor($r('app.color.divider'))
      .setTableInnerBorderColor($r('app.color.divider'))
      .setTodoSelectedColor($r('app.color.text_important'))
      .setUlPointColor($r('app.color.text_secondary'))
      .setFootnoteTextColor($r('app.color.text_secondary'))
      .setLineColor($r('app.color.divider'))
      // ===== 字号统一（float.json 资源管理）=====
      .setTextSize($r('app.float.font_body')) // 正文 = font_body，与用户消息一致
      .setTitleSize([ // 标题 1-6 级字号
        $r('app.float.font_h1'),
        $r('app.float.font_h2'),
        $r('app.float.font_h3'),
        $r('app.float.font_h4'),
        $r('app.float.font_h5'),
        $r('app.float.font_h6'),
      ])
      .setLatexMathTextSize(16) // 公式字号
      // LaTeX 公式颜色：库只接受十六进制 number，手动随系统深浅色切换
      .setLatexMathTextColor(isDark ? 0xFFE5E5E7 : 0xFF1A1A1A)
      .setCodeBlockTheme(isDark ? 'dark' : 'light')
      .setMermaidTheme(isDark ? 'dark' : 'light');
    // 以下两个 setter 返回 void，不能链式调用，需单独设置
    controller.setTableNormalTextColor($r('app.color.text_ai'));
    controller.setTableInterleaveTextColor($r('app.color.text_secondary'));
  }

  // 监听系统配置变化（深色/浅色切换），仅需动态更新字符串/数值类型的主题
  private registerEnvironmentListener(): void {
    const host = this.getUIContext().getHostContext();
    if (host === undefined) {
      return;
    }
    const appCtx = host.getApplicationContext();
    const callback: EnvironmentCallback = {
      onConfigurationUpdated: (config): void => {
        const isDark = config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
        if (isDark !== this.isDarkMode) {
          this.isDarkMode = isDark;
          this.applyMarkdownColors(isDark);
        }
      },
      onMemoryLevel: (level): void => {
        // 内存紧张回调，本组件无需处理
      },
    };
    this.envCallbackId = appCtx.on('environment', callback);
  }

  private unregisterEnvironmentListener(): void {
    const host = this.getUIContext().getHostContext();
    if (host !== undefined && this.envCallbackId !== -1) {
      host.getApplicationContext().off('environment', this.envCallbackId);
      this.envCallbackId = -1;
    }
  }

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
    // 用户消息：保持纯文本渲染（气泡宽度自适应）
    if (this.message.isUser()) {
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
    } else if (this.message.content.length > 0) {
      // AI 消息（lv-markdown-in 原生渲染）：
      //  - 全文直接交给 Markdown 组件，库内置支持 markdown 语法、LaTeX 公式、代码高亮
      //  - mermaid 代码块由库内置的 Mermaid 渲染能力处理（自带 mermaid.main.js），无需自建 WebView
      //  - 流式输出时 text 为 @Prop，chunk 增量自动重绘（库内部支持 streamingActive）
      Column() {
        Markdown({
          text: this.message.content,
          mode: "text",
          controller: this.mdController,
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
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

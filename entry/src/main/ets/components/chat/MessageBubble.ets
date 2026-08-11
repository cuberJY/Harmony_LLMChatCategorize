/**
 * 聊天气泡组件（状态管理 V2）
 * - 用户消息：右对齐，浅蓝背景
 * - AI 消息：左对齐，白色背景
 */
import { Message } from "../../model/Message";
import { BUBBLE_MAX_WIDTH_RATIO_USER, BUBBLE_MAX_WIDTH_RATIO_AI } from "../../common/AppConstants";
import { Markdown, MarkdownController } from "@luvi/lv-markdown-in";
import { common, ConfigurationConstant, EnvironmentCallback } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction, SymbolGlyphModifier, window } from '@kit.ArkUI';
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
  @Local isTextSheetShow: boolean = false; // 「选择文本」半模态面板显示状态（bindSheet $$ 双向绑定）
  // 对话分支：变体信息与操作回调（父组件注入）
  @Param variantCurrent: number = 0; // 当前变体序号（1 起，驱动 "< 4 / 5 >" 中的 4）
  @Param variantTotal: number = 0; // 分支组变体总数（驱动 "5"）
  // 注意：不通过 @Param 传入"流式生成中"标志——@Param 在渲染时冻结，流式结束后不会刷新，
  // 会导致操作栏永久隐藏（必须切页面重建列表才恢复）。改用 message.isStreaming（@Trace 实时驱动）。
  @Event onRegenerate: (msg: Message) => void = () => {}; // 「重新生成」：覆盖当前回复
  @Event onCreateBranch: (msg: Message) => void = () => {}; // 「新建分支」：保留旧回复生成新变体
  @Event onEdit: (msg: Message) => void = () => {}; // 「编辑」：回填输入框创建新分支
  @Event onSwitchBranch: (msg: Message, delta: number) => void = () => {}; // 「< >」切换变体
  @Event onDelete: (msg: Message) => void = () => {}; // 「删除」：删除单条消息（含后续分支）
  @Event onResume: (msg: Message) => void = () => {}; // 「继续生成」：暂停态下从未完成处续写
  // lv-markdown-in 的样式/拦截控制器（普通成员即可，无需响应式）
  private mdController: MarkdownController = new MarkdownController();
  private envCallbackId: number = -1; // 系统环境监听回调 ID（aboutToDisappear 注销用）

  aboutToAppear(): void {
    // 依据当前系统颜色模式配置 Markdown 颜色与代码块/思维导图主题
    this.applyMarkdownTheme();
    this.mdController
      // 1. 开启长按选中文本
      .setTextSelectionEnable(true)
      // 2. 选中后点击"复制"回调——自行写入系统剪贴板
      .setTextSelectionCopyListener((text: string) => {
        const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
        pasteboard.getSystemPasteboard().setData(data)
          .then(() => {
            this.getUIContext().getPromptAction().showToast({ message: $r('app.string.copied') });
          })
          .catch(() => {
            this.getUIContext().getPromptAction().showToast({ message: $r('app.string.copy_failed') });
          });
      })
      // 3. 可选：代码块右上角"复制"按钮
      .setCodeCopyListener((text: string) => {
        const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
        pasteboard.getSystemPasteboard().setData(data)
          .then(() => {
            this.getUIContext().getPromptAction().showToast({ message: $r('app.string.code_copied') });
          });
      });
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
      .setLazyRender(true) // 屏幕外块先用轻量占位渲染
      .setLazyPreloadBlockCount(2) // 仅预渲染可视区附近少量块
      .setThreadRenderEnable(true) // 线程渲染（默认已开，可显式声明）
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
      // 字号统一（float.json 资源管理）
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
      .setCodeBlockIdxState(true) // 代码块是否显示行号索引（可减少渲染节点，提升长代码块滚动性能）
      .setCodeBlockAutoCollapseEnable(true) // 超过阈值(默认10行)的代码块自动折叠，长代码块渲染压力大时受益
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
        // 底部操作栏（复制/编辑/重新生成/新建分支/切换分支）
        // 流式生成中不显示操作栏（isStreaming 为 @Trace，流式结束自动恢复显示）
        if (!this.message.isStreaming) {
          this.actionBar();
        }
      }
      .alignItems(this.message.isUser() ? HorizontalAlign.End : HorizontalAlign.Start)
      // 关键：Column 显式撑满整行（不能 wrap-content 自适应），
      // 否则子元素 actionBar 的 width("100%") 会按外层整行约束解析，把气泡与操作栏撑开错位
      .width("100%")
    }
    .width("100%")
    // 气泡与操作栏已由内部 alignItems 统一对齐（用户贴右 / AI 贴左），
    // 整行不再需要 justifyContent
    .padding({
      left: $r('app.float.space_md'),
      right: $r('app.float.space_md'),
      top: $r('app.float.space_sm'),
      bottom: $r('app.float.space_sm'),
    })
    // 「选择文本」半模态面板：从下方弹出，高度 = 窗口高 - 状态栏 - 标题栏（顶部与标题栏下缘对齐）
    // $$ 双向绑定：拖拽/点遮罩关闭时框架自动把 isTextSheetShow 置回 false
    .bindSheet($$this.isTextSheetShow, this.textSheet(), {
      height: this.textSheetHeight(),
      dragBar: false,
      showClose: false,
      backgroundColor: $r('app.color.dialog_bg'),
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
          .fontSize($r('app.float.font_body'))
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
            .fontSize($r('app.float.font_thinking'))
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
        })
        .copyOption(CopyOptions.LocalDevice)
    } else if (this.message.content.length > 0) {
      /** 
       * AI 消息（lv-markdown-in 原生渲染）：
       *  - 全文直接交给 Markdown 组件，库内置支持 markdown 语法、LaTeX 公式、代码高亮
       *  - mermaid 代码块由库内置的 Mermaid 渲染能力处理（自带 mermaid.main.js），无需自建 WebView
       *  - 流式输出时 text 为 @Prop，chunk 增量自动重绘（库内部支持 streamingActive）
       */
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

  /**
   * 「选择文本」半模态面板内容
   *  - 顶部标题行：上方居中「选择文本」，右上角叉号关闭
   *  - 下方正文：显示渲染前的原始文本（Markdown 源码），可长按选择/复制
   *  - 面板整体高度由 textSheetHeight() 控制，顶部与页面标题栏下缘对齐
   */
  @Builder
  textSheet() {
    Column() {
      // 标题行：左右等宽占位保证标题居中
      Row() {
        // 左侧占位（与右侧关闭按钮等宽，保证标题视觉居中）
        Row().width($r('app.float.space_xxl'))
        Text($r('app.string.select_text'))
          .fontSize($r('app.float.font_title'))
          .fontWeight(700)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        // 右上角关闭按钮（叉）
        Row() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize($r('app.float.font_icon_md'))
            .fontWeight(700)
            .fontColor([$r('app.color.text_secondary')])
        }
        .width($r('app.float.space_xxl'))
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.isTextSheetShow = false;
        })
      }
      .width("100%")
      .height($r('app.float.title_bar_height'))
      .padding({
        left: $r('app.float.space_xl'),
        right: $r('app.float.space_xl'),
      })
      // 标题行底部分割线
      .border({
        width: { bottom: 1 },
        color: { bottom: $r('app.color.divider') },
      })

      // 渲染前的原始文本（Markdown 源码），copyOption 支持长按选择与复制
      Scroll() {
        Text(this.message.content)
          .fontSize($r('app.float.font_body'))
          .fontColor($r('app.color.text_ai'))
          .copyOption(CopyOptions.LocalDevice)
          .width("100%")
          .padding({
            left: $r('app.float.space_xl'),
            right: $r('app.float.space_xl'),
            top: $r('app.float.space_lg'),
            bottom: $r('app.float.space_lg'),
          })
      }
      .width("100%")
      .layoutWeight(1)
      .align(Alignment.TopStart)
      .scrollBar(BarState.Auto)
    }
    .width("100%")
    .height("100%")
    .backgroundColor($r('app.color.dialog_bg'))
  }

  /**
   * 计算「选择文本」面板高度（vp）：
   * 面板从底部弹出，要求其顶部与页面顶部标题栏下缘对齐，
   * 故 高度 = 窗口高度 - 状态栏高度 - 标题栏高度（窗口/状态栏为 px，统一转 vp）。
   */
  private textSheetHeight(): number {
    try {
      const host = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
      if (host === undefined || host.windowStage === undefined) {
        return 500; // 兜底高度
      }
      // 标题栏高度（float 资源带 'vp' 单位，getNumber 返回 px，需转回 vp）
      const titleBarHeightPx = host.resourceManager.getNumber($r('app.float.title_bar_height').id);
      const titleBarHeight = this.getUIContext().px2vp(titleBarHeightPx);
      const win = host.windowStage.getMainWindowSync();
      // 窗口总高度（px）
      const windowHeightPx = win.getWindowProperties().windowRect.height;
      // 状态栏（顶部安全区）高度（px），非沉浸式窗口时为 0
      const safeTopPx = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM).topRect.height;
      const windowHeight = this.getUIContext().px2vp(windowHeightPx);
      const safeTop = this.getUIContext().px2vp(safeTopPx);
      return Math.max(200, windowHeight - safeTop - titleBarHeight);
    } catch (e) {
      return 500; // 异常兜底，保证面板可显示
    }
  }

  // 底部操作栏（对话分支交互入口）

  /**
   * 操作栏布局：
   *  - 用户消息：右下角 [复制] [编辑] [切换分支]（从左到右）
   *  - AI 消息：
   *     第一行（仅暂停态显示）右上角 [继续生成]
   *     第二行 左下角 [切换分支] [复制]；右下角 [新建分支] [重新生成]
   */
  @Builder
  actionBar() {
    Column() {
      // 第一行（仅暂停态 AI 消息显示）：右上角「继续生成」，其余操作按钮移到第二行
      if (!this.message.isUser() && this.message.isPaused) {
        Row() {
          Row()
            .layoutWeight(1) // 占位，把「继续生成」推到最右
          this.resumeButton();
        }
        .width("100%")
        .justifyContent(FlexAlign.End)
        .margin({ right: $r('app.float.space_xs') })
        .padding({
          top: $r('app.float.space_md'),
          bottom: $r('app.float.space_sm')
        })
      }

      // 第二行：常规操作按钮（用户消息靠右一组 / AI 消息左组+右组）
      Row() {
        if (this.message.isUser()) {
          // 用户消息：一组按钮靠右（删除在复制左端，普通图标无特殊颜色）
          Row() {
            this.iconButton($r("sys.symbol.trash"), () => this.confirmDelete());
            this.iconButton($r("sys.symbol.square_and_square"), () => this.copyMessage());
            this.iconButton($r("sys.symbol.square_and_pencil"), () => this.onEdit(this.message));
            // 仅当存在多个变体时才显示切换分支控件（只有一个分支时隐藏）
            if (this.variantTotal > 1) {
              this.variantSwitcher();
            }
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.End)
        } else {
          // AI 消息：左组（切换分支 + 复制）与右组（新建分支 + 重新生成）
          Row() {
            // 仅当存在多个变体时才显示切换分支控件（只有一个分支时隐藏）
            if (this.variantTotal > 1) {
              this.variantSwitcher();
            }
            this.iconButton($r("sys.symbol.square_and_square"), () => this.copyMessage());
            // 「更多」按钮（dot_grid_2x2，位于复制键右侧）：点击弹出菜单
            this.moreButton();
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Start)

          Row() {
            this.iconButton($r("sys.symbol.trash"), () => this.confirmDelete());
            this.iconButton($r("sys.symbol.circle_and_plus"),
              () => this.onCreateBranch(this.message));
            this.iconButton($r("sys.symbol.arrow_clockwise"),
              () => this.onRegenerate(this.message));
          }
          .margin({ right: $r('app.float.space_xs') })
          .justifyContent(FlexAlign.End)
        }
      }
      .width("100%")
    }
    .width("100%")
  }

  // 「更多」按钮（dot_grid_2x2）：样式与 iconButton 保持一致，点击展开纵向菜单
  @Builder
  moreButton() {
    Row() {
      SymbolGlyph($r("sys.symbol.dot_grid_2x2"))
        .fontSize($r('app.float.font_icon_lg'))
        .fontWeight(700)
        .fontColor([$r('app.color.operation_icon')])
    }
    .padding({
      left: $r('app.float.space_xs'),
      right: $r('app.float.space_xs'),
      top: $r('app.float.space_xs'),
      bottom: $r('app.float.space_xs'),
    })
    .margin({
      left: $r('app.float.space_xs'),
      right: $r('app.float.space_xs'),
      top: $r('app.float.space_xs'),
      bottom: $r('app.float.space_xs')
    })
    .backgroundColor($r('app.color.bubble_bg_ai'))
    // 点击展开菜单：复制 / 选择文本 / 新建分支 / 重新生成 / 删除（默认出现在按钮下方，空间不足自动调整）
    .bindMenu(this.moreMenu())
  }

  // 「更多」菜单：从上到下 = 复制、选择文本、新建分支、重新生成、删除
  @Builder
  moreMenu() {
    Menu() {
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_square'))
          .fontSize($r('app.float.font_icon_lg'))
          .fontWeight(500)
          .fontColor([$r('app.color.operation_icon')]),
        content: $r('app.string.copy'),
      })
        .onChange(() => {
          this.copyMessage();
        })
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.doc_plaintext'))
          .fontSize($r('app.float.font_icon_lg'))
          .fontWeight(500)
          .fontColor([$r('app.color.operation_icon')]),
        content: $r('app.string.select_text'),
      })
        .onChange(() => {
          // 打开「选择文本」半模态面板（显示渲染前的原文）
          this.isTextSheetShow = true;
        })
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.circle_and_plus'))
          .fontSize($r('app.float.font_icon_lg'))
          .fontWeight(500)
          .fontColor([$r('app.color.operation_icon')]),
        content: $r('app.string.create_branch'),
      })
        .onChange(() => {
          this.onCreateBranch(this.message);
        })
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_clockwise'))
          .fontSize($r('app.float.font_icon_lg'))
          .fontWeight(500)
          .fontColor([$r('app.color.operation_icon')]),
        content: $r('app.string.regenerate'),
      })
        .onChange(() => {
          this.onRegenerate(this.message);
        })
      // 删除：置于菜单最下面，图标与文字变红（危险操作醒目提示）
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash'))
          .fontSize($r('app.float.font_icon_lg'))
          .fontWeight(500)
          .fontColor([$r('app.color.text_danger')]),
        content: $r('app.string.delete'),
      })
        .contentFontColor($r('app.color.text_danger'))
        .onChange(() => {
          this.confirmDelete();
        })
    }
  }

  // 通用图标按钮：无文字仅图标（操作栏仅在非流式时显示，按钮恒可用）
  @Builder
  iconButton(icon: Resource, action: () => void) {
    Row() {
      SymbolGlyph(icon)
        .fontSize($r('app.float.font_icon_lg'))
        .fontWeight(700)
        .fontColor([$r('app.color.operation_icon')])
    }
    .padding({
      left: $r('app.float.space_xs'),
      right: $r('app.float.space_xs'),
      top: $r('app.float.space_xs'),
      bottom: $r('app.float.space_xs'),
    })
    .margin({
      left: $r('app.float.space_xs'),
      right: $r('app.float.space_xs'),
      top: $r('app.float.space_xs'),
      bottom: $r('app.float.space_xs')
    })
    .backgroundColor($r('app.color.bubble_bg_ai'))
    .onClick(() => {
      action();
    })
  }

  // 「继续生成」胶囊按钮：仅暂停态显示，样式与输入区「深度思考」「联网搜索」开关一致
  //（圆角胶囊 + active 蓝底白字），点击从未完成处续写
  @Builder
  resumeButton() {
    Text($r('app.string.continue_generate'))
      .fontSize($r('app.float.font_button'))
      .fontColor($r('app.color.text_ai'))
      .padding({
        left: $r('app.float.space_sm'),
        right: $r('app.float.space_sm'),
        top: $r('app.float.space_xs'),
        bottom: $r('app.float.space_xs'),
      })
      .height(30)
      .borderRadius(15)
      .backgroundColor($r('app.color.bubble_bg_ai'))
      .border({ width: 1, color: $r('app.color.bubble_bg_thinking') })
      .onClick(() => {
        this.onResume(this.message);
      })
  }

  // 分支切换控件：< 当前 / 总数 >（点击两侧箭头在变体间循环切换；操作栏仅在非流式时显示，恒可切换）
  @Builder
  variantSwitcher() {
    Row() {
      SymbolGlyph($r("sys.symbol.chevron_left"))
        .fontSize($r('app.float.font_icon_md'))
        .fontWeight(700)
        .fontColor([$r('app.color.text_secondary')])
        .padding({
          left: $r('app.float.space_sm'),
          right: $r('app.float.space_sm')
        })
        .onClick(() => {
          this.onSwitchBranch(this.message, -1);
        })
      Text(`${this.variantCurrent} / ${this.variantTotal}`)
        .fontSize($r('app.float.font_icon_md'))
        .fontWeight(500)
        .fontColor($r('app.color.operation_icon'))
        .padding({
          left: $r('app.float.space_xs'),
          right: $r('app.float.space_xs')
        })
      SymbolGlyph($r("sys.symbol.chevron_right"))
        .fontSize($r('app.float.font_icon_md'))
        .fontWeight(700)
        .fontColor([$r('app.color.text_secondary')])
        .padding({
          left: $r('app.float.space_sm'),
          right: $r('app.float.space_sm')
        })
        .onClick(() => {
          this.onSwitchBranch(this.message, 1);
        })
    }
    .padding({
      top: $r('app.float.space_xs'),
      bottom: $r('app.float.space_xs')
    })
    .backgroundColor($r('app.color.bubble_bg_ai'))
  }

  /** 复制整条消息正文到系统剪贴板 */
  private copyMessage(): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.message.content);
    pasteboard.getSystemPasteboard().setData(data)
      .then(() => {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.copied') });
      })
      .catch(() => {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.copy_failed') });
      });
  }

  /**
   * 「删除」确认弹窗：系统对话框二次确认，避免误删
   * 用户点「删除」按钮（index=1）才真正回调 onDelete；取消/点遮罩关闭不删除
   */
  private confirmDelete(): void {
    this.getUIContext().getPromptAction().showDialog({
      title: $r('app.string.delete_message_title'),
      message: $r('app.string.delete_message_confirm'),
      buttons: [
        { text: $r('app.string.cancel'), color: $r('app.color.text_secondary') },
        { text: $r('app.string.delete'), color: $r('app.color.text_danger') },
      ],
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      // index=0 取消，index=1 删除
      if (result.index === 1) {
        this.onDelete(this.message);
      }
    }).catch(() => {
      // 取消或对话框关闭失败，无需处理
    });
  }
}

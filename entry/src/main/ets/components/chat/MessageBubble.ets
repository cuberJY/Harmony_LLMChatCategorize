/**
 * 聊天气泡组件（状态管理 V2）
 * - 用户消息：右对齐，浅蓝背景
 * - AI 消息：左对齐，白色背景
 */
import { Message, ImageAttachment } from "../../model/Message";
import { BUBBLE_MAX_WIDTH_RATIO_USER, BUBBLE_MAX_WIDTH_RATIO_AI } from "../../common/AppConstants";
import { Markdown, MarkdownController } from "@luvi/lv-markdown-in";
import { common, ConfigurationConstant, EnvironmentCallback } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { showDeleteConfirm, showToast, stripMarkdown } from "../../common/Utils";
import { MessageErrorCard } from "./MessageErrorCard";

/**
 * 思考过程块（渲染用）：
 *  - paragraph：连续思考段落（内部保留换行，仅段落首行显示深度思考图标）
 *  - search / browse：搜索/浏览活动行（各自带独立图标，天然分隔思考段落）
 *
 * @ObservedV2/@Trace：块实例在流式过程中被原地复用更新（见 rebuildReasoningBlocks），
 * text 变化时 Text(block.text) 走属性级响应实时刷新——组件无需重建，
 * 规避 ForEach "key 不变 → 内容停留创建时快照" 导致的流式更新失效
 */
@ObservedV2
class ReasoningBlock {
  @Trace kind: "paragraph" | "search" | "browse" = "paragraph";
  @Trace text: string = ""; // paragraph = 整段思考文本；search/browse = 去掉前缀后的文案

  constructor(kind: "paragraph" | "search" | "browse", text: string) {
    this.kind = kind;
    this.text = text;
  }
}

@ComponentV2
export struct MessageBubble {
  /**
   * @Param 父组件传入的 @ObservedV2 消息对象。
   * message 上的 @Trace 属性（content / reasoning / isThinking / isStreaming 等）变化时自动刷新本组件，
   * 流式输出过程即依赖此机制实时重绘气泡。
   */
  @Param message: Message = new Message("", "user", "");

  /* UI 本地状态（@Local，仅组件内部维护） */
  @Local isReasoningExpanded: boolean = true; // 是否展开思考/搜索过程块
  @Local isDarkMode: boolean = false; // 跟随系统深浅色（驱动代码块/思维导图主题切换）
  /**
   * 半模态面板已提升至 ChatPage 页面级统一管理（本组件不再挂 bindSheet）：
   * item 级 bindSheet 在 LazyForEach 中随消息回收/重建，弹层生命周期与 item 耦合易残留遮罩拦截触摸，
   * 故改为通过 onOpenSheet 回调通知页面打开（弹层生命周期与页面绑定，关闭状态由页面统一复位）
   */
  @Local reasoningBlocks: ReasoningBlock[] = []; // 思考过程块列表（流式增量原地复用更新，见 rebuildReasoningBlocks）
  /**
   * 状态点号动画阶段（0/1/2 对应 "思考中."/"思考中.."/"思考中..."）：
   * @Local 变化自动触发标题/状态提示 Text 重绘，驱动周期切换
   */
  @Local dotPhase: number = 0;

  /**
   * 监听折叠请求：ViewModel 在流式结束后延迟 500ms 复查"用户在底部且未操作"再放行（自增 foldVersion）。
   * 气泡收到信号立即动画收起——500ms 缓冲与条件复查全部在 ViewModel 完成，
   * 避免"放行时刻与执行时刻分离"留下窗口：用户滑离底部后仍在阅读位置外收缩，造成页面跳动
   */
  @Monitor('message.foldVersion')
  onFoldRequested(): void {
    if (this.message.reasoning.length === 0) {
      return; // 无思考内容（如仅搜索/正文场景）无需折叠
    }
    if (this.message.isStreaming) {
      return; // 正在重新生成（继续生成/换个回答）：保持展开，不打断新流
    }
    if (!this.isReasoningExpanded) {
      return; // 已被用户手动折叠，无需再动
    }
    /**
     * 用 200ms EaseOut 动画平滑收起：高度收缩由过渡动画吸收，
     * 避免钉底态下视口内容突兀位移（"弹一下"），与页面正文跟随动画时长风格一致
     */
    this.getUIContext().animateTo({ duration: 200, curve: 'easeOut' }, () => {
      this.isReasoningExpanded = false;
    });
  }

  /**
   * 监听思考内容变化：增量重解析并原地复用更新块列表。
   * ForEach 的 key 固定为 index（append-only 下稳定），块文本经 @Trace 属性级刷新，
   * 避免 "key 不变 → 组件不重建 → 流式内容停留旧快照"（表现为思考逐行渲染、切页重建才恢复块渲染）
   */
  @Monitor('message.reasoning')
  onReasoningChanged(): void {
    this.rebuildReasoningBlocks();
  }

  /**
   * 监听思考/搜索状态切换：消息处于任一状态时启动点号动画定时器，全部结束时停止。
   * （isThinking/isSearching 互斥，任一为 true 即说明仍在思考或搜索过程中）
   */
  @Monitor('message.isThinking', 'message.isSearching')
  onStatusChanged(): void {
    this.syncStatusDotTimer();
  }

  /* 对话分支：变体信息与操作回调（父组件注入） */
  /**
   * 注意：不通过 @Param 传入"流式生成中"标志——@Param 在渲染时冻结，流式结束后不会刷新，
   * 会导致操作栏永久隐藏（必须切页面重建列表才恢复）。改用 message.isStreaming（@Trace 实时驱动）。
   */
  @Param variantCurrent: number = 0; // 当前变体序号（1 起，驱动 "< 4 / 5 >" 中的 4）
  @Param variantTotal: number = 0; // 分支组变体总数（驱动 "5"）
  /**
   * 是否为激活链最后一条消息：仅最后一条显示「换个回答」，
   * 避免在历史消息上重新生成导致上下文混乱（由 ChatPage 按 LazyForEach index 传入）
   */
  @Param isLastMessage: boolean = false;
  @Param editingMessageId: string = ""; // 正在编辑的用户消息 id（编辑中的消息禁止删除）
  @Event onRegenerate: (msg: Message) => void = () => {}; // 「换个回答」：覆盖当前回复
  @Event onCreateBranch: (msg: Message) => void = () => {}; // 「生成新回复」：保留旧回复生成新变体
  @Event onEdit: (msg: Message) => void = () => {}; // 「编辑」：回填输入框创建新分支
  @Event onSwitchBranch: (msg: Message, delta: number) => void = () => {}; // 「< >」切换变体
  @Event onDelete: (msg: Message) => void = () => {}; // 「删除」：删除单条消息（含后续分支）
  @Event onResume: (msg: Message) => void = () => {}; // 「继续生成」：暂停态下从未完成处续写
  /**
   * 打开半模态面板（页面级统一管理）：kind = "text"「选择文本」/ "web"「xx个网页」。
   * ChatPage 收到后设置 sheet 状态并弹出（弹层生命周期与页面绑定，避免 item 级 bindSheet 残留）
   */
  @Event onOpenSheet: (msg: Message, kind: "text" | "web") => void = () => {};
  @Event onShare: (msg: Message) => void = () => {}; // 「更多」菜单-分享
  /* 图片全屏预览（页面级统一管理）：点击用户消息图片缩略图时上报消息与下标，ChatPage 弹出预览层 */
  @Event onImagePreview: (msg: Message, index: number) => void = () => {};

  /* 非响应式成员（普通成员即可，无需观察） */
  private mdController: MarkdownController = new MarkdownController(); // lv-markdown-in 样式/拦截控制器
  private envCallbackId: number = -1; // 系统环境监听回调 ID（aboutToDisappear 注销用）
  private statusDotTimer: number = -1; // 状态点号动画定时器 ID（-1 表示未运行）
  /* 增量解析状态（流式 O(n) 优化）：已解析过的 reasoning 快照与未闭合段落块引用 */
  private parsedReasoning: string = ""; // 已解析快照（非追加变化时触发全量重建）
  private lastParagraph: ReasoningBlock | null = null; // 未闭合段落块（增量续写目标）
  private paragraphOpen: boolean = false; // 上一段增量是否以"无换行"的未闭合片段结尾

  aboutToAppear(): void {
    /* 初始化过程块：当前消息的 reasoning（历史完整或流式已有）先解析为块列表；
       后续流式增量由 @Monitor('message.reasoning') 驱动原地更新 */
    this.rebuildReasoningBlocks();
    /* 进入对话记录时默认折叠思考过程：非流式的历史消息（isStreaming=false）初始即为折叠态；
       流式中的新消息（创建时已置 isStreaming=true）保持展开以实时展示思考内容 */
    if (!this.message.isStreaming) {
      this.isReasoningExpanded = false;
    }
    /* 依据当前系统颜色模式配置 Markdown 颜色与代码块/思维导图主题 */
    this.applyMarkdownTheme();
    this.mdController
      /* 1. 开启长按选中文本 */
      .setTextSelectionEnable(true)
      /* 2. 选中后点击"复制"回调——自行写入系统剪贴板 */
      .setTextSelectionCopyListener((text: string) => {
        const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
        pasteboard.getSystemPasteboard().setData(data)
          .then(() => {
            showToast($r('app.string.copied'));
          })
          .catch(() => {
            showToast($r('app.string.copy_failed'));
          });
      })
      /* 3. 可选：代码块右上角"复制"按钮 */
      .setCodeCopyListener((text: string) => {
        const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
        pasteboard.getSystemPasteboard().setData(data)
          .then(() => {
            showToast($r('app.string.code_copied'));
          });
      });
    this.registerEnvironmentListener();
    /* 初始若已处于思考/搜索中（如创建即置 isThinking 的消息），立即启动点号动画 */
    this.syncStatusDotTimer();
  }

  aboutToDisappear(): void {
    this.unregisterEnvironmentListener();
    this.stopStatusDotTimer();
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
    /* 链式部分（返回 this 的 setter） */
    const controller = this.mdController
      .setLazyRender(true) // 屏幕外块先用轻量占位渲染
      .setLazyPreloadBlockCount(2) // 仅预渲染可视区附近少量块
      .setThreadRenderEnable(true) // 线程渲染（默认已开，可显式声明）
      .setTitleColor($r('app.color.font_primary'))
      .setTextColor($r('app.color.font_primary'))
      .setInlineCodeColor($r('app.color.font_emphasize'))
      .setInlineCodeBackgroundColor($r('app.color.bubble_bg_thinking'))
      .setQuoteTextColor($r('app.color.font_secondary'))
      .setQuoteBorderColor($r('app.color.divider'))
      .setQuoteBackgroundColor($r('app.color.bubble_bg_thinking'))
      .setHyperlinkTextColor($r('app.color.font_emphasize'))
      .setHyperlinkBackgroundColor(Color.Transparent)
      .setTableTitleTextColor($r('app.color.font_primary'))
      .setTableTitleBackgroundColor($r('app.color.bubble_bg_thinking'))
      .setTableBackgroundColor($r('app.color.bubble_bg_ai'))
      .setTableInterleaveBackgroundColor($r('app.color.bubble_bg_thinking'))
      .setTableOuterBorderColor($r('app.color.divider'))
      .setTableInnerBorderColor($r('app.color.divider'))
      .setTodoSelectedColor($r('app.color.font_emphasize'))
      .setUlPointColor($r('app.color.font_secondary'))
      .setFootnoteTextColor($r('app.color.font_secondary'))
      .setLineColor($r('app.color.divider'))
      /* 字号统一（float.json 资源管理） */
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
      /* LaTeX 公式颜色：库只接受十六进制 number，手动随系统深浅色切换 */
      .setLatexMathTextColor(isDark ? 0xFFE5E5E7 : 0xFF1A1A1A)
      .setCodeBlockTheme(isDark ? 'dark' : 'light')
      .setCodeBlockIdxState(true) // 代码块是否显示行号索引（可减少渲染节点，提升长代码块滚动性能）
      .setCodeBlockAutoCollapseEnable(true) // 超过阈值(默认10行)的代码块自动折叠，长代码块渲染压力大时受益
      .setMermaidTheme(isDark ? 'dark' : 'light');
    /* 以下两个 setter 返回 void，不能链式调用，需单独设置 */
    controller.setTableNormalTextColor($r('app.color.font_primary'));
    controller.setTableInterleaveTextColor($r('app.color.font_secondary'));
  }

  /* 监听系统配置变化（深色/浅色切换），仅需动态更新字符串/数值类型的主题 */
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
        /* 内存紧张回调，本组件无需处理 */
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
        /* 仅 AI 消息且有思考内容时显示 */
        if (!this.message.isUser() && this.message.reasoning.length > 0) {
          this.reasoningBlock();
        }
        /* 正文气泡 */
        if (this.message.isUser()) {
          this.bubbleContent($r('app.color.font_primary'), $r('app.color.bubble_bg_user'));
        } else {
          this.bubbleContent($r('app.color.font_primary'), $r('app.color.bubble_bg_ai'));
        }
        /* 生成终止错误卡片（AI 消息且有结构化错误时显示；正文保持纯净，错误信息独立呈现） */
        if (!this.message.isUser() && this.message.error !== undefined) {
          MessageErrorCard({ error: this.message.error });
        }
        /**
         * 底部操作栏（复制/编辑/换个回答/生成新回复/切换分支）。
         * 流式生成中不显示（isStreaming 为 @Trace，流式结束自动恢复显示）
         */
        if (!this.message.isStreaming) {
          this.actionBar();
        }
      }
      .alignItems(this.message.isUser() ? HorizontalAlign.End : HorizontalAlign.Start)
      /**
       * 关键：Column 显式撑满整行（不能 wrap-content 自适应），
       * 否则子元素 actionBar 的 width("100%") 会按外层整行约束解析，把气泡与操作栏撑开错位
       */
      .width("100%")
    }
    .width("100%")
    /**
     * 气泡与操作栏已由内部 alignItems 统一对齐（用户贴右 / AI 贴左），
     * 整行不再需要 justifyContent
     */
    .padding({
      left: $r('app.float.space_md'),
      right: $r('app.float.space_md'),
      top: $r('app.float.space_sm'),
      bottom: $r('app.float.space_sm'),
    });
  }

  /* 半模态面板内容（sheetContent/textSheet/textSheetHeight）已整体上提至 ChatPage 页面级管理 */

  @Builder
  reasoningBlock() {
    Column() {
      /* 标题行：点击可折叠/展开（阶段优先：搜索 > 思考 > 已思考） */
      Row() {
        Text(
          this.message.isSearching
            ? `搜索中${this.statusDots()}`
            : this.message.isThinking
              ? `思考中${this.statusDots()}`
              : `已思考（用时 ${this.message.thinkingDuration} 秒）`,
        )
          .fontSize($r('app.float.font_body'))
          .fontColor($r('app.color.font_secondary'))
          .margin({ left: $r('app.float.space_xxs') })
          .layoutWeight(1)
        /* 折叠/展开箭头 */
        SymbolGlyph(
          this.isReasoningExpanded ? $r("sys.symbol.chevron_down") : $r("sys.symbol.chevron_right"),
        )
          .fontSize($r('app.float.font_icon_md'))
          .fontWeight(600)
          .fontColor([$r('app.color.font_secondary')])
          .margin({
            right: this.isReasoningExpanded ? $r('app.float.space_sm') : $r('app.float.space_md'),
          })
      }
      .onClick(() => {
        this.isReasoningExpanded = !this.isReasoningExpanded;
      })

      /**
       * 过程内容正文（展开时显示）：思考文本与搜索/浏览活动按真实到达顺序穿插在同一序列（reasoning）里，
       * 按块渲染（rebuildReasoningBlocks 维护块列表）：思考段落整段展示（仅首行带深度思考图标），
       * 【搜索】行带放大镜图标，【浏览】行带链接图标
       */
      if (this.isReasoningExpanded) {
        ForEach(this.reasoningBlocks, (block: ReasoningBlock, index: number) => {
          this.processBlock(block);
          /**
           * key 只用 id + index：reasoning 是纯追加（append-only），块序列只增不减，
           * index 对已有块恒定、新增块递增，天然唯一且稳定。
           * 块文本变化走 ReasoningBlock 的 @Trace 属性刷新（rebuildReasoningBlocks 原地复用），
           * 因此 key 无需包含内容，也不会出现"流式内容停留旧快照"或逐 chunk 重建的抖动
           */
        }, (block: ReasoningBlock, index: number) => `block_${this.message.id}_${index}`)
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
    .margin({ bottom: $r('app.float.space_sm') });
  }

  /**
   * 状态点号动画（"思考中." → "思考中.." → "思考中..." 周期循环，300ms/拍）：
   *  - dotPhase 为 @Local，setInterval 定时递增触发标题/状态提示 Text 属性级重绘
   *  - 定时器仅在思考/搜索期间运行（@Monitor 与 aboutToAppear/Disappear 同步启停），避免空转
   */
  private syncStatusDotTimer(): void {
    if (this.message.isSearching || this.message.isThinking) {
      this.startStatusDotTimer();
    } else {
      this.stopStatusDotTimer();
    }
  }

  /* 启动点号循环：每 300ms dotPhase 在 0/1/2 间递进（1/2/3 个点） */
  private startStatusDotTimer(): void {
    if (this.statusDotTimer !== -1) {
      return; // 已在运行
    }
    this.statusDotTimer = setInterval(() => {
      this.dotPhase = (this.dotPhase + 1) % 3;
    }, 500);
  }

  /* 停止点号循环并复位，下次从 1 个点重新开始 */
  private stopStatusDotTimer(): void {
    if (this.statusDotTimer !== -1) {
      clearInterval(this.statusDotTimer);
      this.statusDotTimer = -1;
    }
    this.dotPhase = 0;
  }

  /* 按 dotPhase 生成点号：0/1/2 → "." / ".." / "..." */
  private statusDots(): string {
    return this.dotPhase === 0 ? " ." : (this.dotPhase === 1 ? " . ." : " . . .");
  }

  /**
   * 解析思考过程为"块"序列（流式增量版）：
   *  - reasoning 纯追加时只解析增量后缀并原地复用块（O(增量)，替代原每 30ms 全量 O(n)）
   *  - 出现清空/替换/回退（重新生成、分支切换等）时回退全量重建
   */
  private rebuildReasoningBlocks(): void {
    const reasoning = this.message.reasoning;
    if (this.parsedReasoning.length === 0 || !reasoning.startsWith(this.parsedReasoning)) {
      /* 非追加（清空/替换/回退）→ 全量重建 */
      this.fullRebuildReasoningBlocks(reasoning);
      return;
    }
    if (reasoning.length === this.parsedReasoning.length) {
      return; // 无新增
    }
    const suffix = reasoning.slice(this.parsedReasoning.length);
    this.parsedReasoning = reasoning;
    this.appendReasoningSuffix(suffix);
  }

  /* 全量重建（首次 / 回归场景） */
  private fullRebuildReasoningBlocks(reasoning: string): void {
    const lines = reasoning.split('\n');
    const blocks: ReasoningBlock[] = [];
    let paragraph: string[] = [];
    const flushParagraph = (): void => {
      if (paragraph.length > 0) {
        blocks.push(new ReasoningBlock("paragraph", paragraph.join('\n')));
        paragraph = [];
      }
    };
    for (const line of lines) {
      if (line.startsWith("【搜索】") || line.startsWith("【浏览】")) {
        flushParagraph();
        blocks.push(new ReasoningBlock(
          line.startsWith("【搜索】") ? "search" : "browse",
          line.substring(4),
        ));
      } else if (line.trim().length === 0) {
        flushParagraph();
      } else {
        paragraph.push(line);
      }
    }
    flushParagraph();
    this.reasoningBlocks = blocks;
    this.parsedReasoning = reasoning;
    /**
     * 修复：全量重建后若文本未以换行结尾，说明末行仍是未闭合片段，
     * 后续增量需直接续接（否则段落会被错误切成两个块）
     */
    this.paragraphOpen = reasoning.length > 0 && !reasoning.endsWith('\n');
    this.lastParagraph = blocks.length > 0 && blocks[blocks.length - 1].kind === "paragraph"
      ? blocks[blocks.length - 1]
      : null;
  }

  /* 追加增量后缀（suffix = reasoning 自上次解析后的新增部分） */
  private appendReasoningSuffix(suffix: string): void {
    let lines = suffix.split('\n');
    /* 上一段以未闭合片段结尾 → 首段是该片段的直接延续（无换行） */
    if (this.paragraphOpen && this.lastParagraph !== null) {
      this.lastParagraph.text += lines[0];
      lines = lines.slice(1);
      if (lines.length === 0) {
        return; // 纯续写，段落保持打开
      }
      this.paragraphOpen = false;
    }
    /* 完整行（每行都以换行结尾） */
    for (let i = 0; i < lines.length - 1; i++) {
      this.appendReasoningLine(lines[i]);
    }
    /* 尾部片段：非空说明行未闭合，保持段落打开等待续写；空串说明以换行结尾 */
    const tail = lines[lines.length - 1];
    if (tail.length > 0) {
      this.appendReasoningLine(tail);
      this.paragraphOpen = true;
    } else {
      this.paragraphOpen = false;
    }
  }

  /* 处理一个完整行（或以无换行结尾的尾部片段） */
  private appendReasoningLine(line: string): void {
    if (line.startsWith("【搜索】") || line.startsWith("【浏览】")) {
      this.closeLastParagraph();
      this.reasoningBlocks.push(new ReasoningBlock(
        line.startsWith("【搜索】") ? "search" : "browse",
        line.substring(4),
      ));
    } else if (line.trim().length === 0) {
      this.closeLastParagraph(); // 空行 = 段落分隔
    } else {
      if (this.lastParagraph === null) {
        this.lastParagraph = new ReasoningBlock("paragraph", line);
        this.reasoningBlocks.push(this.lastParagraph);
      } else {
        this.lastParagraph.text += "\n" + line;
      }
    }
  }

  /* 关闭未闭合段落（搜索/浏览活动行、空行到来时调用） */
  private closeLastParagraph(): void {
    this.lastParagraph = null;
  }

  /* 过程块渲染：行首 4 字符前缀（【搜索】/【浏览】）由 rebuildReasoningBlocks 识别为块类型，文案统一 substring(4) 去掉前缀，界面只显示"图标 + 文案" */
  @Builder
  processBlock(block: ReasoningBlock) {
    if (block.kind === "search") {
      /* 【搜索】 活动行 */
      Row() {
        SymbolGlyph($r("sys.symbol.AI_search"))
          .fontSize($r('app.float.font_icon_sm'))
          .fontWeight(600)
          .fontColor([$r('app.color.search_icon')])
          .margin({
            right: $r('app.float.space_sm'),
            top: $r('app.float.space_xxs')
          })
        Text(block.text)
          .fontSize($r('app.float.font_thinking'))
          .fontColor($r('app.color.font_secondary'))
          .lineHeight($r('app.float.line_height_thinking'))
          .layoutWeight(1)
      }
      .alignItems(VerticalAlign.Top)
      .margin({
        left: $r('app.float.space_xs'),
        right: $r('app.float.space_md'),
        top: $r('app.float.space_sm')
      })
    } else if (block.kind === "browse") {
      /* 【浏览】 活动行 */
      Row() {
        SymbolGlyph($r("sys.symbol.link"))
          .fontSize($r('app.float.font_icon_sm'))
          .fontWeight(600)
          .fontColor([$r('app.color.search_icon')])
          .margin({
            right: $r('app.float.space_sm'),
            top: $r('app.float.space_xxs')
          })
        Text(block.text)
          .fontSize($r('app.float.font_thinking'))
          .fontColor($r('app.color.font_secondary'))
          .lineHeight($r('app.float.line_height_thinking'))
          .layoutWeight(1)
      }
      .alignItems(VerticalAlign.Top)
      .margin({
        left: $r('app.float.space_xs'),
        right: $r('app.float.space_md'),
        top: $r('app.float.space_sm')
      })
    } else {
      /* 连续思考段落：整段一个图标，段内行距收紧 */
      Row() {
        SymbolGlyph($r("sys.symbol.AI_deep_thinking"))
          .fontSize($r('app.float.font_icon_sm'))
          .fontWeight(600)
          .fontColor([$r('app.color.font_secondary')])
          .margin({
            right: $r('app.float.space_sm'),
            top: $r('app.float.space_xxs')
          })
        Text(block.text)
          .fontSize($r('app.float.font_thinking'))
          .fontColor($r('app.color.font_secondary'))
          .lineHeight($r('app.float.line_height_thinking'))
          .layoutWeight(1)
      }
      .alignItems(VerticalAlign.Top)
      .margin({
        left: $r('app.float.space_xs'),
        right: $r('app.float.space_xs'),
        top: $r('app.float.space_sm')
      })
    }
  }

  @Builder
  bubbleContent(fontColor: ResourceColor, bgColor: ResourceColor) {
    /* 用户消息：图片网格 + 正文（气泡宽度自适应；图片位于上方，正文保留纯文本渲染） */
    if (this.message.isUser()) {
      /* 图片附件：多图自动换行缩略图，点击全屏预览 */
      if (this.message.images.length > 0) {
        this.userImagesGrid()
      }
      /* 有正文才渲染文本（纯图片消息不显示空文本占位；图片在上方时正文加顶距） */
      if (this.message.content.length > 0) {
        Text(this.message.content)
          .fontSize($r('app.float.font_body'))
          .fontColor(fontColor)
          .copyOption(CopyOptions.LocalDevice)
          .margin({
            top: this.message.images.length > 0 ? $r('app.float.space_sm') : 0,
          })
        .padding({
          left: $r('app.float.bubble_padding_h'),
          right: $r('app.float.bubble_padding_h'),
          top: $r('app.float.bubble_padding_v'),
          bottom: $r('app.float.bubble_padding_v'),
        })
        .borderRadius($r('app.float.bubble_radius'))
        .backgroundColor(bgColor)
        .constraintSize({
          maxWidth: `${BUBBLE_MAX_WIDTH_RATIO_USER * 100}%`,
        })
      }
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
      /**
       * AI 消息、正文为空：显示阶段状态（优先级：搜索 > 失败 > 思考中）
       * 搜索细节（正在搜索/正在浏览）已写入 reasoning 时由过程块展示，这里仅在过程为空时显示扫描线提示，避免重复
       */
      if (this.message.isSearching && this.message.reasoning.length === 0) {
        this.statusHint("正在搜索", true);
      } else if (this.message.searchFailed) {
        this.statusHint("联网搜索失败，使用普通模式回答");
      } else if (this.message.isThinking && this.message.reasoning.length === 0) {
        this.statusHint("思考中", true);
      }
      /* 若 reasoning 非空（有推理内容），推理块标题本身会显示"思考中…"，这里留空避免重复 */
    }
  }

  /**
   * 用户消息图片网格（最多 9 张）：
   * Flex 自动换行 + 固定尺寸正方形缩略图（Base64 data URL 渲染），点击上报全屏预览
   */
  @Builder
  userImagesGrid() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.End }) {
      ForEach(
        this.message.images,
        (img: ImageAttachment, idx: number) => {
          Image('data:' + img.mimeType + ';base64,' + img.data)
            .width(72)
            .height(72)
            .borderRadius($r('app.float.bubble_radius'))
            .objectFit(ImageFit.Cover)
            .backgroundColor($r('app.color.divider'))
            /* 共享元素转场：与 PreviewPage 全屏图同 id（preview_+img.id），点击放大衔接
               Navigation 环境下用 geometryTransition（sharedTransition 仅 router 路由生效） */
            .geometryTransition('preview_' + img.id)
            .alignSelf(ItemAlign.End)
            .margin({
              left: $r('app.float.space_xs'),
              bottom: $r('app.float.space_xxs')
            })
            .onClick(() => {
              this.onImagePreview(this.message, idx);
            })
        },
        (img: ImageAttachment) => img.id,
      )
    }
    .width('100%')
  }

  @Builder
  statusHint(text: string, animated: boolean = false) {
    Text(animated ? `${text}${this.statusDots()}` : text)
      .fontSize($r('app.float.font_body'))
      .fontColor($r('app.color.font_secondary'))
      .padding({
        left: $r('app.float.bubble_padding_h'),
        right: $r('app.float.bubble_padding_h'),
        top: $r('app.float.bubble_padding_v'),
        bottom: $r('app.float.bubble_padding_v'),
      })
      .borderRadius($r('app.float.bubble_radius'))
      .backgroundColor($r('app.color.bubble_bg_ai'));
  }

  /* 「选择文本」/「xx个网页」面板已上提至 ChatPage（本文件不再持有面板 Builder 与高度计算） */

  /* 底部操作栏（对话分支交互入口） */

  /* 操作栏布局：用户消息右下角 [复制][编辑][切换分支]；AI 消息第一行（暂停态）右上角 [继续生成]，第二行左 [切换分支][复制]、右 [生成新回复][换个回答] */
  @Builder
  actionBar() {
    Column() {
      /* 第一行（AI 消息）：左侧「xx个网页」按钮（有浏览记录即显示，与是否暂停对话无关）+ 右上角「继续生成」（仅暂停态） */
      if (!this.message.isUser() && (this.message.isPaused || this.message.searchedWebs.length > 0)) {
        Row() {
          /* 左「xx个网页」按钮（仅当有浏览记录时显示） */
          if (this.message.searchedWebs.length > 0) {
            this.webButton();
          }
          Row()
            .layoutWeight(1) // 占位，把「继续生成」推到最右
          /* 右「继续生成」（仅暂停态显示） */
          if (this.message.isPaused) {
            this.resumeButton();
          }
        }
        .width("100%")
        .justifyContent(FlexAlign.Start)
        .padding({
          left: $r('app.float.space_sm'),
          right: $r('app.float.space_sm'),
          top: $r('app.float.space_md'),
          bottom: $r('app.float.space_sm')
        })
      }

      /* 第二行：常规操作按钮（用户消息靠右一组 / AI 消息左组+右组） */
      Row() {
        if (this.message.isUser()) {
          /* 用户消息：一组按钮靠右 */
          Row() {
            this.iconButton($r("sys.symbol.trash"), () => this.confirmDelete());
            this.iconButton($r("sys.symbol.square_and_square"), () => this.copyMessage());
            this.iconButton($r("sys.symbol.square_and_pencil"), () => this.onEdit(this.message));
            /* 仅当存在多个变体时才显示切换分支控件（只有一个分支时隐藏） */
            if (this.variantTotal > 1) {
              this.variantSwitcher();
            }
          }
          .layoutWeight(1)
          .margin({ right: $r('app.float.space_xs') })
          .justifyContent(FlexAlign.End)
        } else {
          /* AI 消息： */
          Row() {
            /* 仅当存在多个变体时才显示切换分支控件（只有一个分支时隐藏） */
            if (this.variantTotal > 1) {
              this.variantSwitcher();
            }
            /* 「更多」按钮（位于复制键右侧） */
            this.moreButton();
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Start)

          Row() {
            /* 「换个回答」 */
            if (this.isLastMessage) {
              this.iconButton($r("sys.symbol.arrow_clockwise"),
                () => {
                  this.isReasoningExpanded = true; // 重新生成时自动展开思考过程
                  this.onRegenerate(this.message);
                });
            }
            this.iconButton($r("sys.symbol.trash"), () => this.confirmDelete());
            this.iconButton($r("sys.symbol.square_and_square"), () => this.copyMessage());
            this.iconButton($r("sys.symbol.circle_and_plus"),
              () => this.onCreateBranch(this.message));
          }
          .margin({ right: $r('app.float.space_xs') })
          .justifyContent(FlexAlign.End)
        }
      }
      .width("100%")
    }
    .width("100%")
  }

  /* 「更多」按钮（dot_grid_2x2）：样式与 iconButton 一致 */
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
    .backgroundColor($r('app.color.page_bg'))
    /* 点击展开菜单：复制 / 选择文本 / 生成新回复 / 换个回答 / 删除（默认出现在按钮下方，空间不足自动调整） */
    .bindMenu(this.moreMenu())
  }

  /* 「更多」菜单：复制、选择文本、生成新回复、换个回答（仅最后一条）、删除 */
  @Builder
  moreMenu() {
    Menu() {
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_square'))
          .fontSize($r('app.float.font_icon_lg'))
          .fontWeight(500)
          .fontColor([$r('app.color.operation_icon')]),
        content: "复制",
      })
        .onChange(() => {
          this.copyMessage();
        })
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.share'))
          .fontSize($r('app.float.font_icon_lg'))
          .fontWeight(500)
          .fontColor([$r('app.color.operation_icon')]),
        content: "分享",
      })
        .onChange(() => {
          this.onShare(this.message);
        })
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.doc_plaintext'))
          .fontSize($r('app.float.font_icon_lg'))
          .fontWeight(500)
          .fontColor([$r('app.color.operation_icon')]),
        content: "选择文本",
      })
        .onChange(() => {
          /* 打开「选择文本」半模态面板（页面级统一管理） */
          this.onOpenSheet(this.message, "text");
        })
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.circle_and_plus'))
          .fontSize($r('app.float.font_icon_lg'))
          .fontWeight(500)
          .fontColor([$r('app.color.operation_icon')]),
        content: "生成新回复",
      })
        .onChange(() => {
          this.onCreateBranch(this.message);
        })
      /* 「换个回答」（仅激活链最后一条显示） */
      if (this.isLastMessage) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_clockwise'))
            .fontSize($r('app.float.font_icon_lg'))
            .fontWeight(500)
            .fontColor([$r('app.color.operation_icon')]),
          content: "换个回答",
        })
          .onChange(() => {
            this.isReasoningExpanded = true; // 重新生成时自动展开思考过程
            this.onRegenerate(this.message);
          })
      }
      /* 删除：置于菜单最下面，图标与文字变红（危险操作醒目提示） */
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash'))
          .fontSize($r('app.float.font_icon_lg'))
          .fontWeight(500)
          .fontColor([$r('app.color.text_danger')]),
        content: "删除",
      })
        .contentFontColor($r('app.color.text_danger'))
        .onChange(() => {
          this.confirmDelete();
        })
    }
  }

  /* 通用图标按钮：无文字仅图标（操作栏仅在非流式时显示，按钮恒可用） */
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
      left: $r('app.float.space_sm'),
      right: $r('app.float.space_sm'),
      top: $r('app.float.space_xs'),
      bottom: $r('app.float.space_xs')
    })
    .backgroundColor($r('app.color.page_bg'))
    .onClick(() => {
      action();
    })
  }

  /* 「继续生成」胶囊按钮：仅暂停态显示，样式与输入区「深度思考」「联网搜索」开关一致（圆角胶囊 + active 蓝底白字） */
  @Builder
  resumeButton() {
    Text("继续生成")
      .fontSize($r('app.float.font_toggle'))
      .fontColor($r('app.color.font_primary'))
      .padding({
        left: $r('app.float.space_sm'),
        right: $r('app.float.space_sm'),
        top: $r('app.float.space_xs'),
        bottom: $r('app.float.space_xs'),
      })
      .height(30)
      .borderRadius(15)
      .backgroundColor($r('app.color.page_bg'))
      .border({ width: 1, color: $r('app.color.operation_icon') })
      .onClick(() => {
        this.isReasoningExpanded = true; // 继续生成时自动展开思考过程
        this.onResume(this.message);
      })
  }

  /* 「xx个网页」按钮：操作栏第一行最左侧，展示浏览过的网页数量，点击弹出网页面板（显示条件仅 searchedWebs 非空） */
  @Builder
  webButton() {
    Row() {
      SymbolGlyph($r("sys.symbol.pc_ic_tab_index"))
        .fontSize($r('app.float.font_icon_lg'))
        .fontWeight(600)
        .fontColor([$r('app.color.search_icon')])
        .margin({ right: $r('app.float.space_xs') })
      Text(`${this.message.searchedWebs.length} 个网页`)
        .fontSize($r('app.float.font_toggle'))
        .fontColor($r('app.color.font_primary'))
    }
    .padding({
      left: $r('app.float.space_sm'),
      right: $r('app.float.space_sm'),
      top: $r('app.float.space_xs'),
      bottom: $r('app.float.space_xs'),
    })
    .height(30)
    .borderRadius(15)
    .backgroundColor($r('app.color.page_bg'))
    .border({ width: 1, color: $r('app.color.operation_icon') })
    .onClick(() => {
      /* 打开「xx个网页」半模态面板（页面级统一管理） */
      this.onOpenSheet(this.message, "web");
    })
  }

  /* 分支切换控件：< 当前 / 总数 >（点击两侧箭头在变体间循环切换；操作栏仅在非流式时显示，恒可切换） */
  @Builder
  variantSwitcher() {
    Row() {
      SymbolGlyph($r("sys.symbol.chevron_left"))
        .fontSize($r('app.float.font_icon_lg'))
        .fontWeight(700)
        .fontColor([$r('app.color.operation_icon')])
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
        .fontSize($r('app.float.font_icon_lg'))
        .fontWeight(700)
        .fontColor([$r('app.color.operation_icon')])
        .padding({
          left: $r('app.float.space_sm'),
          right: $r('app.float.space_sm')
        })
        .onClick(() => {
          this.onSwitchBranch(this.message, 1);
        })
    }
    .padding({
      right: $r('app.float.space_xs'),
      top: $r('app.float.space_xs'),
      bottom: $r('app.float.space_xs')
    })
    .backgroundColor($r('app.color.page_bg'))
  }

  private copyMessage(): void {
    /* 修复：AI 消息复制纯文本（去掉 Markdown 标记），用户消息原文复制 */
    const text = this.message.isUser() ? this.message.content : stripMarkdown(this.message.content);
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data)
      .then(() => {
        showToast($r('app.string.copied'));
      })
      .catch(() => {
        showToast($r('app.string.copy_failed'));
      });
  }

  /**
   * 「删除」确认弹窗：统一走 showDeleteConfirm（showAlertDialog 封装）二次确认，避免误删
   * 用户点「删除」才真正回调 onDelete；取消/点遮罩关闭不删除
   * 编辑中的消息直接 toast 提示，不进入确认弹窗（其内容正回填在输入框中）
   */
  private confirmDelete(): void {
    if (this.editingMessageId === this.message.id) {
      showToast($r('app.string.edit_delete_forbidden'));
      return;
    }
    showDeleteConfirm(
      this.getUIContext(),
      "删除消息",
      "确定删除该消息吗？删除后将同时删除该消息后续的所有分支",
      () => {
        this.onDelete(this.message);
      },
    );
  }
}

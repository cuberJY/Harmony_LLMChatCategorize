/**
 * 聊天页 ViewModel（状态管理 V2）
 * 承载 ChatPage 的数据与业务逻辑：
 *   - 消息列表数据源（IDataSource，供 LazyForEach 使用）
 *   - 对话加载 / 新建 / 标题同步
 *   - 发送消息 + AI 流式回复（联网搜索、思考计时、节流刷新）
 *   - 列表滚动控制
 *
 * 页面（ChatPage）只保留：build 布局、路由跳转、页面过渡动画；
 * UI 需要观察的状态用 @Trace 声明，页面 build 中通过 this.vm.xxx 读取，变化时自动刷新
 */

import { common } from "@kit.AbilityKit";
import { DatabaseHelper } from "../database/DatabaseHelper";
import { ConversationRepository } from "../database/ConversationRepository";
import { Conversation } from "../model/Conversation";
import { Message, ImageAttachment, FileAttachment } from "../model/Message";
import { StreamCallbacks } from "../service/provider/LLMProvider";
import { StreamTask } from "../service/StreamTask";
import { LLMProviderFactory } from "../service/LLMProviderFactory";
import { AppConfig } from "../config/AppConfig";
import { ThinkingEffort, DEFAULT_THINKING_EFFORT, isVisionModel } from "../config/ModelPresets";
import { showToast, getGlobalUiContext } from "../common/Utils";
import { LLMError, ErrorCode, errorMessageResource, buildError } from "../service/LLMError";
import { BackgroundRunGuardService } from "../service/BackgroundRunGuardService";
import { FileParser } from "../service/FileParser";
import { Logger } from "../common/Logger";
import { MessageDataSource } from "./MessageDataSource";
import { BranchChainManager, VariantInfo } from "./BranchChainManager";

/**
 * 空回复自动续试次数上限：completed 但无正文（联网搜索后模型空回复）时自动重试，
 * 连续重试达到上限仍无正文才落回"暂停态"提示用户
 */
const MAX_AUTO_RETRY: number = 2;

/**
 * AI 生成/占位标题的最大字符数：硬截断上限。
 * normalizeTitle（AI 标题清洗）与首条消息占位标题共用，保证长度口径一致
 */
const MAX_TITLE_LENGTH: number = 25;

/**
 * 标题自动生成的最大尝试次数：generateTitle 失败（网络/解析等）时保留待生成标记，
 * 后续任意首轮终态事件会再次尝试；连续失败超过该次数后放弃（保留占位标题，用户可手动重命名）
 */
const MAX_TITLE_ATTEMPTS: number = 2;

/**
 * 切换分支后的"锚点静默期"（ms）：从切换开始到补偿完成前抑制自动钉底，
 * 覆盖新变体 Markdown 异步渲染增高窗口，避免补偿滚动触发 onReachEnd 后又被渲染增高钉到底部
 */
const ANCHOR_SUPPRESS_MS: number = 1000;

/**
 * 流式 UI 刷新间隔（ms）：chunk 先攒进缓冲区，按此间隔合并写入 content/reasoning 触发重绘，
 * 将高频增量降为较低频率的 UI 更新，减少渲染与滚动竞争
 */
const STREAM_FLUSH_INTERVAL_MS: number = 30;

/**
 * 阶段5 历史排版补齐项：当前会话历史中某条用户消息的 docx/pptx 附件
 * （已持久化源文件 localPath 但 pageImages 为空，视觉模型下补齐排版图后 updateMessage 落库）
 */
interface ReparseItem {
  msg: Message;
  file: FileAttachment;
}

@ObservedV2
export class ChatViewModel {
  /* 供其他页面（侧边栏删除对话）取消流任务的静态入口（应用内仅一个 ChatPage 实例） */
  private static currentInstance: ChatViewModel | null = null;

  static getInstance(): ChatViewModel | null {
    return ChatViewModel.currentInstance;
  }

  /* UI 可观察状态（@Trace：页面 build 中读取，变化时自动刷新） */

  @Trace isAtBottom: boolean = true;
  @Trace title: string = "新对话";
  @Trace modelName: string = "";
  /* 编辑态：正在编辑的用户消息 id（空串 = 非编辑态），UI 据此显示编辑提示 */
  @Trace editingMessageId: string = "";
  /* 编辑态：回填到底部输入框的原始内容 */
  @Trace editingPrefill: string = "";
  /* 编辑态：回填到底部输入框的原始图片（编辑时可增删改；纯文本模型下带图消息禁止编辑） */
  @Trace editingPrefillImages: ImageAttachment[] = [];
  /* 编辑态：回填到底部输入框的原始文件（编辑时可增删改；纯文本模型下带 pdf 的消息禁止编辑） */
  @Trace editingPrefillFiles: FileAttachment[] = [];
  /**
   * 底部输入区开关状态（唯一真源：发送 / 重新生成 / 新建分支共用）
   * ChatInput 切换时通过 updateSearchOptions 实时同步，
   * 保证「重新生成/新建分支」使用当前开关，而非上次发送时的值
   */
  @Trace webSearch: boolean = true;
  @Trace thinkingEffort: ThinkingEffort = DEFAULT_THINKING_EFFORT;
  /**
   * 当前对话的流式生成状态（唯一真源，驱动 ChatInput 的发送/暂停键与「继续生成」按钮）
   * - idle：无进行中的任务 → 显示发送键
   * - streaming：生成中 → 发送键变为暂停键（点击暂停）
   * - paused：已暂停（用户点暂停键或网络异常中断）→ 显示「继续生成」按钮
   */
  @Trace streamState: "idle" | "streaming" | "paused" = "idle";
  /* 当前模型是否支持图片输入（驱动 ChatInput 选图按钮显隐；onPageShow 与模型切换时刷新） */
  @Trace supportsVision: boolean = false;
  /**
   * 激活链最后一条消息 id（驱动 MessageBubble 的「换个回答」显隐）。
   * 数据驱动替代 LazyForEach index 快照：删除/分支切换后 @Trace 变化 → ChatPage build 重跑
   * → item @Param 更新，避免"删除后新最后一条不显示「换个回答」"的陈旧问题
   */
  @Trace lastMessageId: string = "";

  /* 供页面 build 绑定的对象 */

  listScroller: Scroller = new Scroller();
  messageDataSource: MessageDataSource = new MessageDataSource();
  /* 分支链管理器（持有全量消息缓存与变体信息缓存，承接分支链构建/变体统计等数据逻辑） */
  private branchManager: BranchChainManager = new BranchChainManager();

  /* 非状态成员（内部逻辑用） */
  private dbInitPromise: Promise<void> = Promise.resolve(); // 数据库初始化完成信号
  private currentConversation: Conversation = new Conversation(); // 当前对话对象
  private currentConversationId: string = ""; // 当前对话 id
  private isFirstUserMsg: boolean = true; // 是否第一条用户消息（决定是否生成标题）
  /**
   * 待生成标题的对话 id（addMessage 首条用户消息时记录；首轮 AI 回复完成后生成标题并清空）。
   * 独立于"当前对话"判断：即使流式期间切换对话，后台流完成后仍能为该对话生成标题，
   * 不会因切走导致标记残留、标题永不生成
   */
  private pendingTitleConvId: string = "";
  /* 标题生成尝试计数（convId -> 已尝试次数）：成功或放弃时清除，配合 MAX_TITLE_ATTEMPTS 限制反复失败 */
  private titleAttempts: Map<string, number> = new Map();
  private isUserOperating: boolean = false; // 用户是否正在操作屏幕（操作中停止自动滚底）
  private lastScrollIsUserGesture: boolean = false; // 最近一次滚动是否来自用户手势（onWillScroll 更新，供 onReachEnd 区分用户滚回 vs 代码滚动）
  private isUserScrolling: boolean = false; // 用户是否正在滚动手势中（DRAG/FLING/滚动条等）；期间暂停流式 UI 写入，避免底部高度变化与滚动竞争抖动
  private pendingAutoFold: Message[] = []; // 流式结束时思考块折叠请求挂起（含 500ms 延迟窗口），条件满足时统一放行
  private autoFoldFlushTimerId: number = -1; // 折叠延迟放行的调度定时器（500ms 窗口内用户滑离底部则保留挂起）
  private followAnimationTimerId: number = -1; // 流式正文跟随动画的防抖定时器（-1 表示无挂起）
  private scrollAnimator?: (action: () => void) => void; // 页面注入的滚动动画执行器（getUIContext().animateTo）
  private isListLayoutReady: boolean = false; // List 是否已完成首帧布局（onAreaChange 首次回调置位）
  private pendingPinToBottom: boolean = false; // 布局就绪前挂起的钉底请求
  private pendingFocusIndex: number = -1; // 布局就绪前挂起的搜索定位消息下标（-1=无挂起）
  private isRestoringAnchor: boolean = false; // 切换分支锚点恢复期间置位：抑制 onListItemHeightChanged 的自动钉底干扰
  private anchorSuppressUntil: number = 0; // 切换分支后抑制自动钉底的截止时间戳（ms）：覆盖 Markdown 异步渲染增高窗口
  private isDestroyed: boolean = false; // 页面销毁标记（销毁后流回调跳过 UI 更新）
  /**
   * 是否有「切换分支(纯浏览,persist=false)」产生的未落库激活链变更：
   * 发送新消息前必须先固化激活链到 DB，防止生成在首个 token 前失败/进程被杀时
   * DB 中残留两条 is_active=1 的链，导致新消息重载后不可见
   */
  private pendingActiveChainPersist: boolean = false;
  /**
   * 进行中的流式任务表：key = 对话 id，一个对话最多一个进行中的流
   * 支持多对话并行流式：切走后原对话的流仍在后台推进，切回时由 loadConversation 重新挂载
   */
  private streamTasks: Map<string, StreamTask> = new Map();
  /* 各对话"流式增量持久化"的最后写库时间戳（节流：避免每个 chunk 都写库） */
  private streamPersistTime: Map<string, number> = new Map();

  /* 生命周期（由页面生命周期回调转发） */

  /* 页面 aboutToAppear：初始化数据库（页面级 UIAbilityContext） */
  aboutToAppear(context: common.UIAbilityContext): void {
    if (!context) return;
    /* 保存 init promise：发送首条消息前 await，避免数据库未就绪时消息丢失 */
    this.dbInitPromise = DatabaseHelper.getInstance()
      .init(context)
      .then(() => {
        this.currentConversationId = this.currentConversation.id;
      });
  }

  /* 页面 aboutToDisappear：标记销毁并清理所有进行中任务的定时器，防止内存泄漏 */
  aboutToDisappear(): void {
    if (ChatViewModel.currentInstance === this) {
      ChatViewModel.currentInstance = null;
    }
    this.isDestroyed = true;
    if (this.followAnimationTimerId >= 0) {
      clearTimeout(this.followAnimationTimerId);
      this.followAnimationTimerId = -1;
    }
    this.streamTasks.forEach((task: StreamTask) => {
      task.clearTimer();
    });
  }

  /**
   * 页面每次显示时触发（首页首次进入 / 从侧边栏返回）
   * - 刷新模型名（设置页可能已修改）
   * - 回读最新标题（重命名可能发生在侧边栏，当前页对象与侧边栏对象不是同一个实例）
   * 注：选中对话的加载由页面 Navigation onPop 回调调用 loadConversation 完成，不再走全局标记
   */
  onPageShow(): void {
    this.modelName = AppConfig.getInstance().getModel();
    this.supportsVision = isVisionModel(AppConfig.getInstance().getModel());
    this.syncTitleFromDb();
    this.verifyCurrentConversation();
  }

  /* 当前对话已在数据库被删除（侧边栏删除后返回）→ 重置为新对话，避免残留消息 */
  private async verifyCurrentConversation(): Promise<void> {
    const id = this.currentConversationId;
    if (id.length === 0) return; // 空白新对话尚未入库，跳过（避免误判为"已删除"）
    const conv = await ConversationRepository.getInstance().getById(id);
    if (this.currentConversationId !== id) return; // 查询期间对话已切换，丢弃过期结果
    if (!conv) {
      this.newConversation(); // 已删除 → 清空消息列表并进入"新对话"
    }
  }

  /* 对话管理 */

  /* 新建对话：创建新对话对象、清空消息列表（不立即入库，等待首条用户消息） */
  newConversation(): void {
    this.messageDataSource.clear();
    this.branchManager.clearAll();
    this.lastMessageId = ""; // 空列表无最后一条（驱动「换个回答」显隐重置）
    this.currentConversation = new Conversation();
    this.currentConversationId = this.currentConversation.id;
    this.isFirstUserMsg = true;
    this.pendingTitleConvId = ""; // 新对话：等首条用户消息落库时再标记待生成标题
    this.titleAttempts.clear(); // 新对话：清空标题生成尝试计数
    this.editingMessageId = "";
    this.editingPrefill = "";
    this.editingPrefillImages = [];
    this.title = "新对话";
    this.resetScrollFollow(); // 新对话 → 恢复自动跟随
    this.pendingActiveChainPersist = false; // 新对话无未落库的分支切换
    this.pendingAutoFold = []; // 清空上个对话挂起的折叠请求
    this.streamState = "idle"; // 新对话无进行中任务，恢复发送键
  }

  /**
   * 加载指定历史对话：替换消息列表 + 更新标题
   * 并发要点：
   *   - await 后校验"仍是该对话"，丢弃过期结果（快速连续切换不会显示错乱）
   *   - 若该对话有进行中的流任务，用内存中的实时 aiMsg 替换 DB 里的空占位，恢复流式显示
   * @param conv 要加载的对话
   * @param focusMessageId 可选的定位消息 ID（搜索面板跳转）：加载后滚动到该消息（屏幕中间）；
   *                       空/未命中激活链时回退滚动到底部
   */
  async loadConversation(conv: Conversation, focusMessageId?: string): Promise<void> {
    /* 1. 更新当前对话状态 */
    this.currentConversation = conv;
    this.currentConversationId = conv.id;
    this.isFirstUserMsg = false; // 历史对话已有消息，不再生成标题
    this.pendingTitleConvId = ""; // 历史对话已有回复，不触发标题生成
    this.editingMessageId = "";
    this.editingPrefill = "";
    this.editingPrefillImages = [];
    this.pendingActiveChainPersist = false; // 切换对话丢弃上个对话的脏标记
    this.pendingAutoFold = []; // 清空上个对话挂起的折叠请求
    this.pendingFocusIndex = -1; // 切换对话放弃上次未执行的搜索定位
    this.title = conv.title.length > 0 ? conv.title : "新聊天";

    /* 2. 从数据库查询该对话的全部消息（含非激活分支变体） */
    const msgs = await ConversationRepository.getInstance().getMessages(conv.id);
    /* 过期结果守卫：查询期间用户又切到其他对话 → 丢弃本次结果 */
    if (this.currentConversationId !== conv.id) {
      return;
    }
    /* 保存全量缓存（分支切换/变体统计/激活链重建的唯真源） */
    this.branchManager.setAll(msgs);

    /**
     * 3. 构建激活链替换列表；若有进行中的流任务，用实时 aiMsg 替换 DB 占位（避免重复）
     * 暂停任务同样处理：暂停时已把部分内容持久化，DB 会返回新实例，
     * 需用内存中的 task.aiMsg（含流式缓冲）替换链中同名占位，保证「继续生成」的增量能实时刷新到列表
     */
    const liveTasks = this.tasksOfConversation(conv.id);
    const hasLiveTask = liveTasks.some((t: StreamTask) => t.isStreaming || t.isPaused);
    /**
     * 修复(双对象分叉)：DB 快照中的占位是空/陈旧实例，必须用内存中的实时 aiMsg
     * 替换缓存内同 id 实例（而非仅在缺失时追加），否则流完成后分支操作会
     * 从缓存重建激活链，把已生成内容回退成空占位
     */
    liveTasks.forEach((t: StreamTask) => {
      this.branchManager.replaceInstance(t.aiMsg);
    });
    let chain = this.branchManager.buildActiveChain();
    /* 按消息 id 逐条替换（多分支各自替换自己的任务占位，互不干扰） */
    chain = chain.map((m: Message) => {
      const t = this.streamTasks.get(m.id);
      return t !== undefined && (t.isStreaming || t.isPaused) ? t.aiMsg : m;
    });
    /* 无任何活跃/暂停任务时才做"进程被终止"的恢复判定（有任务时内存态为准） */
    if (!hasLiveTask) {
      this.restoreInterruptedMessage(chain);
    }
    this.messageDataSource.replaceAll(chain);

    /* 4. 渲染完成后：搜索定位到命中消息（屏幕中间）或滚动到底部 */
    this.syncLastMessageId();
    this.isAtBottom = true;
    this.resetScrollFollow(); // 切换对话 → 恢复自动跟随
    if (focusMessageId !== undefined && focusMessageId.length > 0) {
      const focusIdx = chain.findIndex((m: Message) => m.id === focusMessageId);
      if (focusIdx >= 0) {
        this.isAtBottom = false; // 定位到消息中间：不在底部，避免 item 增高时被钉底逻辑拉回
        this.pinToMessageIndex(focusIdx);
      } else {
        this.pinToBottomAfterLoad(); // 命中消息不在激活链（开关打开命中的非激活变体）→ 回退钉底
      }
    } else {
      this.pinToBottomAfterLoad();
    }
    /* 5. 依据该对话的进行中任务刷新 UI 状态（有流任务→暂停键；暂停任务→继续生成按钮） */
    this.refreshStreamState();
  }

  /**
   * 按 id 从数据库拉取当前对话的最新标题并同步到标题栏
   * （重命名发生在侧边栏，当前页对象与侧边栏对象不是同一个实例）
   */
  async syncTitleFromDb(): Promise<void> {
    const id = this.currentConversationId; // 捕获调用时的对话 id
    if (id.length === 0) return; // 空白新对话尚未入库，跳过
    const conv = await ConversationRepository.getInstance().getById(id);
    /* 查询期间对话可能已切换（onPop 中同步调用 loadConversation），丢弃过期结果避免覆盖新标题 */
    if (!conv || this.currentConversationId !== id) return;
    this.currentConversation.title = conv.title; // 同步内存对象（后续入库/比较用）
    this.title = conv.title.length > 0 ? conv.title : "新对话"; // 同步标题栏
  }

  /**
   * 首轮 AI 回复结束后自动生成对话标题（覆盖截断占位）：
   * 1. 从"当前激活链"取首轮问答（激活链首条 user + 首条 assistant）作为上下文。
   *    修复：不再按 DB 时间序取全量首条——分支一失败后分支二（新变体）完成时，
   *    时间序首条可能是已熄灭的失败分支，导致标题概括错误；只取用户当前看到的激活链
   * 2. 未配置 / 网络失败 / 解析失败 → 保留截断占位（由 maybeGenerateTitle 控制重试）
   * 3. 落库前回读 DB 校验"标题仍是占位"，避免覆盖侧边栏手动重命名（防竞态）；
   *    标题已被手动命名/对话已删除 → 视为"目标已达成"，清空待生成标记
   * @param task 结束的首个流式任务（持有归属对话与 AI 消息）
   */
  private async generateConversationTitle(task: StreamTask): Promise<void> {
    const convId = task.conversationId;
    /* 竞态/用户命名前置校验：回读 DB，若标题已被用户手动命名 → 不再自动生成，清除待生成标记。
       先于占位比对与 LLM 请求，避免对已命名对话浪费一次标题生成调用 */
    const preCheck = await ConversationRepository.getInstance().getById(convId);
    if (preCheck === undefined) {
      this.pendingTitleConvId = ""; // 对话已删除
      this.titleAttempts.delete(convId);
      return;
    }
    if (preCheck.isUserNamed) {
      this.pendingTitleConvId = "";
      this.titleAttempts.delete(convId);
      return;
    }
    /* 触发时标题 = 截断占位（addMessage 首条用户消息写入）；作为"是否被重命名"的比对基线 */
    const placeholderTitle = task.targetConv.title;
    /* assistant 上下文 = 完成任务的消息（内存最终态）：不依赖 DB 写入时序（updateMessage 异步），
     * 也天然是激活链的完成分支——分支一失败后分支二（新变体）完成任务时取其内容概括，
     * 而非按 DB 时间序取到已熄灭的失败分支 */
    const aiMsg: Message | undefined = task.aiMsg;
    /* user 上下文 = 激活链首条用户消息（从 DB 读，早已入库；编辑首轮提问时新变体已同步落库） */
    const msgs = await ConversationRepository.getInstance().getMessages(convId);
    const userMsg: Message | undefined = msgs
      .filter((m: Message) => m.conversationId === convId && m.isActive)
      .sort((a: Message, b: Message) => a.createdAt - b.createdAt)
      .find((m: Message) => m.isUser());
    const context: Message[] = [];
    if (userMsg !== undefined) {
      context.push(userMsg);
    }
    if (aiMsg !== undefined) {
      context.push(aiMsg);
    }
    if (context.length === 0) {
      return; // 上下文缺失（异常场景）→ 保留占位，留待下次终态重试
    }
    const title = await LLMProviderFactory.create().generateTitle(context);
    if (title.length === 0) {
      return; // 生成失败/空 → 保留占位（maybeGenerateTitle 计数控制重试次数）
    }
    const cleanTitle = this.normalizeTitle(title);
    if (cleanTitle.length === 0) {
      return;
    }
    /* 竞态防护：回读 DB，仅当标题仍为占位（未被手动重命名/对话未被删除）时才覆盖 */
    const fresh = await ConversationRepository.getInstance().getById(convId);
    if (fresh === undefined || fresh.title !== placeholderTitle) {
      /* 对话已删除 / 标题已被手动重命名 → 无需再自动生成，清除待生成标记 */
      this.pendingTitleConvId = "";
      this.titleAttempts.delete(convId);
      return;
    }
    fresh.title = cleanTitle;
    ConversationRepository.getInstance().update(fresh);
    /* 标题已成功生成：清空待生成标记与尝试计数（后续分支完成不再触发，保持标题稳定） */
    this.pendingTitleConvId = "";
    this.titleAttempts.delete(convId);
    /* 当前正在展示该对话 → 同步标题栏（@Trace 驱动刷新） */
    if (this.currentConversationId === convId) {
      this.title = cleanTitle;
    }
  }

  /**
   * 首轮回复结束（任意终态：完成 / 输出截断 / 报错 / 网络中断）时触发标题生成：
   * - 仅当 pendingTitleConvId 命中该对话才处理（addMessage 首条用户消息时记录）
   * - 生成成功或标题已定（被重命名 / 对话删除）后由 generateConversationTitle 清空标记
   * - 失败保留标记，最多重试 MAX_TITLE_ATTEMPTS 次后放弃（占位标题保留，用户可手动重命名）
   * @param task 已进入终态的首轮流式任务
   */
  private maybeGenerateTitle(task: StreamTask): void {
    if (this.pendingTitleConvId !== task.conversationId) {
      return; // 非首轮（标题已生成或已放弃）→ 不触发
    }
    const convId = task.conversationId;
    const attempts = this.titleAttempts.get(convId) ?? 0;
    if (attempts >= MAX_TITLE_ATTEMPTS) {
      /* 连续失败超过上限：放弃自动生成，清空标记（避免后续每轮终态反复请求） */
      this.pendingTitleConvId = "";
      this.titleAttempts.delete(convId);
      return;
    }
    this.titleAttempts.set(convId, attempts + 1);
    this.generateConversationTitle(task);
  }

  /**
   * 清洗 AI 生成的标题：去首尾空白/成对引号、压缩换行与多余空白、限制长度
   * 截断时不加省略号：标题要求简短（指令已约束 ≤10 字），截断仅作兜底，直接截取前若干字符
   * @param raw 模型输出的原始标题
   * @returns 规范后的标题；清洗后为空串时返回空串
   */
  private normalizeTitle(raw: string): string {
    let t = raw.trim();
    /* 去掉可能包裹的成对引号（中英文） */
    if ((t.startsWith('"') && t.endsWith('"')) || (t.startsWith('“') && t.endsWith('”'))) {
      t = t.substring(1, t.length - 1).trim();
    }
    /* 压缩内部换行/多余空白为单个空格 */
    t = t.replace(/\s+/g, " ");
    if (t.length === 0) {
      return "";
    }
    /* 兜底截断：直接截取，不加省略号（标题应简短完整） */
    if (t.length > MAX_TITLE_LENGTH) {
      return t.substring(0, MAX_TITLE_LENGTH);
    }
    return t;
  }

  /* 发送消息 + AI 流式回复 */

  /**
   * 处理用户发送：可选联网搜索 + LLM 流式回复
   *
   * 并发要点：
   *   - 捕获当前对话 id 作为任务归属，消息/占位/上下文/任务全部保持一致
   *   - 连发限制按"对话"粒度判断（isStreamingFor），不同对话的流互不影响
   *   - 每个对话一个 StreamTask，缓冲/节流/占位消息全部按任务隔离
   *   - onComplete 只更新 updated_at（避免覆盖流式期间的重命名等字段）
   *
   * 开关状态：联网搜索 / 思考强度由 this.webSearch / this.thinkingEffort 读取
   * （ChatInput 切换时已通过 updateSearchOptions 同步到本 VM，唯一真源）
   *
   * @param text 用户输入文本
   * @param images 图片附件列表（仅视觉模型支持；默认空）
   * @param files 文件附件列表（单文件；txt/md 走文本通道所有模型可用，pdf 页面图仅视觉模型；默认空）
   */
  async handleUserSend(text: string, images: ImageAttachment[] = [], files: FileAttachment[] = []): Promise<void> {
    /* 等待数据库初始化完成，确保首条消息正常入库 */
    await this.dbInitPromise;
    if (this.isDestroyed) return; // 页面已销毁，中止本次发送

    /* 捕获当前对话 id：后续统一用捕获值，保证消息/占位/上下文/任务归属一致 */
    const sendConvId = this.currentConversationId;
    /* 连发限制按"对话"粒度判断（放在 await 之后，避免快速连点两次双双通过检查） */
    if (this.isStreamingFor(sendConvId)) {
      showToast(getGlobalUiContext(), $r("app.string.streaming_busy"));
      return;
    }

    /* 编辑态：该次发送在被编辑的用户消息处创建新变体分支并重新生成（图片/文件用编辑后的结果）。
       文件解析在 editUserMessage 内部占位创建之后进行（同样显示「文件解析中」） */
    if (this.editingMessageId.length > 0) {
      const editTargetId = this.editingMessageId;
      this.exitEditMode();
      await this.editUserMessage(editTargetId, text, this.webSearch, this.thinkingEffort, images, files);
      return;
    }

    /* 1. 创建用户消息（parent = 激活链尾，根消息为空串） */
    const tail = this.messageDataSource.getData(this.messageDataSource.totalCount() - 1);
    const userMsg = this.addMessage("user", text, tail !== undefined ? tail.id : "", images, files);
    this.scrollToBottom();

    /* 2. 创建 AI 占位消息（parent = 刚发送的用户消息），保留引用用于流式填充。
       先进入「文件解析中」状态（isParsing=true）：解析耗时（尤其 pdf 逐页渲染）期间
       气泡立即显示解析进度，解析完成后才转「思考中」 */
    const aiMsg = this.addMessage("assistant", "", userMsg.id);
    aiMsg.isStreaming = true;
    if (files.length > 0) {
      aiMsg.isParsing = true;
    }
    this.scrollToBottom(); // 占位已入列 → 立即滚动到底，让「文件解析中…」状态立即可见

    /* 3. 延迟解析：发送时才解析文件内容（txt/md/xlsx 读文本；pdf 渲染页面图）。
       逐个 await，期间 AI 气泡显示「文件解析中…」；
       失败 → AI 占位保留并转为错误卡片（不删除消息），其余流程终止 */
    if (files.length > 0) {
      try {
        for (const f of files) {
          await FileParser.getInstance().parseForSend(f);
        }
      } catch (e) {
        aiMsg.isParsing = false;
        aiMsg.isStreaming = false;
        aiMsg.error = buildError(ErrorCode.FILE_PARSE_FAILED, (e as Error).message, undefined, "local");
        return;
      }
    }

    /* 3.5 历史排版补齐（阶段5）：视觉模型下，扫描当前会话历史中「docx/pptx + 源文件已持久化 + pageImages 空」的
       附件，逐个补齐排版图（发送前同步完成，保证新消息的 AI 回复能理解历史文件排版）。
       补齐期间 AI 气泡显示「历史文件解析中」；单文件失败仅记日志跳过，不阻断发送（不同于当前文件解析的严格语义） */
    if (isVisionModel(AppConfig.getInstance().getModel())) {
      const pending: ReparseItem[] = this.collectPendingReparse();
      if (pending.length > 0) {
        aiMsg.isParsing = false; // 当前文件解析阶段结束（当前无文件时本就是 false）
        aiMsg.parsingHistory = true;
        this.scrollToBottom();
        for (const item of pending) {
          try {
            await FileParser.getInstance().parseVisualForHistory(item.file);
            ConversationRepository.getInstance().updateMessage(item.msg);
          } catch (e) {
            Logger.warn(`历史排版补齐失败(${item.file.name}): ${JSON.stringify(e)}`);
          }
        }
        aiMsg.parsingHistory = false;
      }
    }

    /* 4. 解析后重算视觉：图片与「无文本兜底」的页面图（pdf）走视觉模型；
       docx/pptx 同时有 textContent（文本兜底）与 pageImages（排版图），双通道皆可用，
       非视觉模型下仅发文本、不拦截。不通过 → AI 占位转为错误卡片（保留用户消息） */
    const hasVisual: boolean = images.length > 0
      || files.some((f: FileAttachment) => f.pageImages.length > 0 && f.textContent.length === 0);
    if (hasVisual && !isVisionModel(AppConfig.getInstance().getModel())) {
      aiMsg.isParsing = false;
      aiMsg.isStreaming = false;
      aiMsg.error = buildError(ErrorCode.FILE_PARSE_FAILED, "当前模型不支持解析PDF文件，请切换模型后重试", undefined, "local");
      return;
    }

    /* 5. 解析完成 → 转为思考态。
       解析结果（textContent/pageImages）修改发生在 addMessage 之后，须补写落库，
       保证重启后文件内容可恢复（历史重解析依赖此数据） */
    aiMsg.isParsing = false;
    aiMsg.isThinking = true;
    aiMsg.thinkingStartTime = Date.now();
    if (files.length > 0) {
      ConversationRepository.getInstance().updateMessage(userMsg);
    }

    /* 6. 构造历史上下文（不含最后一条空 AI 消息），并捕获目标对话 */
    /* 捕获当前对话：流式期间可能切换/新建对话，onComplete 只更新捕获对象，不污染其他对话 */
    const targetConv = this.currentConversation;
    const context: Message[] = this.messageDataSource.getAll().slice(0, -1);

    /* 7. 发起流式回复（任务登记 + 可选搜索 + 回调 + 调用 LLM） */
    this.startStreamReply(sendConvId, targetConv, aiMsg, context, this.webSearch, this.thinkingEffort, text);
  }

  /**
   * 收集当前会话历史中需要补齐排版的附件（阶段5）：
   * 遍历激活链用户消息，筛选「docx/pptx + 源文件已持久化（localPath 非空）+ 尚未渲染排版图（pageImages 空）」。
   * 激活链 = 当前可见分支链，只补齐用户能看到的历史附件
   */
  private collectPendingReparse(): ReparseItem[] {
    const items: ReparseItem[] = [];
    const chain: Message[] = this.branchManager.buildActiveChain();
    chain.forEach((m: Message) => {
      if (!m.isUser() || m.files.length === 0) {
        return;
      }
      m.files.forEach((f: FileAttachment) => {
        if ((f.ext === "docx" || f.ext === "pptx") && f.localPath.length > 0 && f.pageImages.length === 0) {
          items.push({ msg: m, file: f });
        }
      });
    });
    return items;
  }

  /**
   * 同步底部输入区的开关状态（ChatInput 切换时由页面转发）
   * 唯一真源：发送 / 重新生成 / 新建分支 / 编辑均读取此处的当前值，
   * 避免「重新生成/新建分支」误用上一次发送时的开关
   * @param webSearch 联网搜索开关
   * @param thinkingEffort 思考强度（reasoning.effort：none 关闭 / low 轻量 / high 深度 / max 极限）
   */
  updateSearchOptions(webSearch: boolean, thinkingEffort: ThinkingEffort): void {
    this.webSearch = webSearch;
    this.thinkingEffort = thinkingEffort;
  }

  /**
   * 发起一次 AI 流式回复（普通发送 / 重新生成 / 新建分支 / 编辑 共用入口）
   * @param sendConvId 归属对话 id
   * @param targetConv 发起时捕获的对话对象（onComplete 刷新 updated_at 用）
   * @param aiMsg AI 占位消息（流式填充目标；重新生成时复用旧消息对象实现覆盖）
   * @param context 历史上下文（不含 aiMsg 本身）
   * @param webSearch 是否开启联网搜索（服务端 web_search 工具）
   * @param thinkingEffort 思考强度（reasoning.effort：none 关闭 / low 轻量 / high 深度 / max 极限）
   * @param searchQuery 保留参数（历史版本为本地搜索取词；服务端搜索后不再使用）
   */
  private async startStreamReply(
    sendConvId: string,
    targetConv: Conversation,
    aiMsg: Message,
    context: Message[],
    webSearch: boolean,
    thinkingEffort: ThinkingEffort,
    searchQuery: string,
    resetOnFirstChunk: boolean = false, // 「换个回答」覆盖模式：首增量前保留旧内容
  ): Promise<void> {
    /* 用户主动发起生成（发送/重新生成/新建分支/编辑/继续生成）→ 恢复自动跟随 */
    this.resetScrollFollow();
    /**
     * 0. 若 aiMsg 本身已登记"暂停"任务（重新生成/编辑复用同一条消息）→ 新请求接管。
     *    仅清理同一条消息的任务，不误删其他分支的暂停任务（多分支互不干扰）
     */
    const existing = this.streamTasks.get(aiMsg.id);
    if (existing !== undefined && existing.isPaused) {
      existing.clearTimer();
      existing.aiMsg.isPaused = false; // 任务被新请求接管，气泡上不再显示「继续生成」
      this.streamTasks.delete(aiMsg.id);
    }

    /* 1. 登记流式任务（替代原全局 isStreaming 标志，实现按消息/分支隔离） */
    const task = new StreamTask(sendConvId, aiMsg, targetConv);
    task.webSearchEnabled = webSearch; // 记录本次是否请求联网搜索（onComplete 据此判断搜索是否发生过）
    task.resetOnFirstChunk = resetOnFirstChunk;
    task.thinkingEffort = thinkingEffort; // 记录本次思考强度（「继续生成」时复用）
    /* 流式进行中 → 生成状态标记为未完成（进程终止时重启可识别并恢复「继续生成」） */
    aiMsg.generationStatus = "partial";
    this.streamTasks.set(task.aiMsg.id, task);
    /* 同步进行中任务数到保活服务（退后台时据此决定是否申请长时任务） */
    this.syncBackgroundGuardCount();
    /* 当前对话正是发起方 → UI 进入"生成中"态（发送键变为暂停键） */
    if (this.currentConversationId === sendConvId) {
      this.streamState = "streaming";
    }

    /* 2. 构造回调并调用 LLM Provider（回调统一操作 task，实现按对话隔离） */
    this.startProviderStream(task, context, thinkingEffort, webSearch, "");
  }

  /**
   * 「换个回答」覆盖模式的延迟清空：首个增量（思考或正文）到达时才清空旧内容，
   * 若新生成在收到任何增量前失败，旧回答得以保留（错误卡片叠加显示）
   */
  private ensureStreamReset(task: StreamTask): void {
    if (!task.resetOnFirstChunk) {
      return;
    }
    task.resetOnFirstChunk = false;
    task.aiMsg.content = "";
    task.aiMsg.reasoning = "";
  }

  /**
   * 构造流式回调并调用 LLM Provider（普通发送 / 重新生成 / 新建分支 / 编辑 / 继续生成 共用）
   * @param task 已登记的任务对象（「继续生成」时复用原任务，保持 aiMsg / 归属一致）
   * @param context 本次请求的上下文（「继续生成」时末尾含已生成部分内容的 AI 消息）
   * @param thinkingEffort 思考强度（reasoning.effort：none 关闭 / low 轻量 / high 深度 / max 极限）
   * @param webSearch 联网搜索开关
   * @param baseContent 本次请求前 aiMsg 已含的正文（onComplete 用 baseContent+fullText 写回，
   *   避免"继续生成"时仅剩本次增量而覆盖掉暂停前已生成的内容）
   */
  private startProviderStream(
    task: StreamTask,
    context: Message[],
    thinkingEffort: ThinkingEffort,
    webSearch: boolean,
    baseContent: string,
  ): void {
    const aiMsg = task.aiMsg;
    const callbacks: StreamCallbacks = {
      /* 思考内容增量 → 攒到任务缓冲，节流刷新 */
      onReasoningChunk: (deltaReasoning: string) => {
        if (this.isDestroyed) return; // 页面已销毁：跳过 UI 更新
        this.ensureStreamReset(task); // 覆盖模式：首个增量前清空旧内容/旧思考（思考先行时同样生效）
        task.beginThinking(); // 多阶段思考：每段思考开始时恢复"思考中"状态（重新计时）
        /* AI 首次思考 → 对话置顶（排序依据 updatedAt） */
        this.markConversationActive(task);
        task.reasoningBuffer += deltaReasoning;
        this.scheduleFlush(task);
      },
      /* 正文增量 → 攒到任务缓冲，节流刷新 */
      onChunk: (deltaText: string) => {
        if (this.isDestroyed) return;
        this.ensureStreamReset(task); // 覆盖模式：首个增量前清空旧内容/旧思考
        aiMsg.searchFailed = false;
        if (aiMsg.isSearching) {
          aiMsg.isSearching = false; // 收到正文 = 服务端搜索已结束
        }
        /* 收到正文 = 当前思考阶段结束（结算该阶段耗时并累计；后续可能再进入下一段思考） */
        task.endThinking();
        /* AI 首次输出正文 → 对话置顶（覆盖 普通发送/继续生成/重新生成/新建分支/编辑） */
        this.markConversationActive(task);
        task.streamBuffer += deltaText;
        this.scheduleFlush(task);
      },
      /* 服务端开始执行联网搜索 */
      onWebSearchStart: () => {
        if (this.isDestroyed) return;
        task.searchEventSeen = true;
        aiMsg.isSearching = true;
      },
      /**
       * 搜索词已确定（output_item.done 携带）：把"正在搜索：xxx"活动行追加到过程序列
       * 过程序列即 aiMsg.reasoning：思考增量与搜索活动按真实到达顺序穿插累积，UI 按行渲染时自然穿插显示
       */
      onSearchQuery: (queries: string[]) => {
        if (this.isDestroyed) return;
        /* 先写入未 flush 的思考增量，保证活动行严格插在已产生的思考文本之后（时间顺序） */
        task.flush();
        aiMsg.reasoning += `\n【搜索】正在搜索：${queries.join("、")}`;
      },
      /* 模型正在浏览页面（open_page 动作）：把"正在浏览 xxx 域名"活动行追加到过程序列 */
      onSearchBrowse: (url: string) => {
        if (this.isDestroyed) return;
        task.flush();
        aiMsg.reasoning += `\n【浏览】正在浏览 ${this.extractDomain(url)}`;
        /* 结构化记录浏览过的网页（按完整 URL 去重）：@Trace 驱动「xx个网页」按钮数量与面板列表实时刷新 */
        const exists = aiMsg.searchedWebs.find(w => w.url === url) !== undefined;
        if (!exists) {
          aiMsg.searchedWebs.push({ url: url, domain: this.extractDomain(url) });
        }
      },
      /* 服务端搜索完成（模型开始基于搜索结果回答） */
      onWebSearchEnd: () => {
        if (this.isDestroyed) return;
        task.searchEventSeen = true;
        aiMsg.isSearching = false;
      },
      onComplete: (fullText: string) => {
        /* 先把未 flush 的增量写入消息（重点：思考内容尾部不能丢），再统一收尾 */
        task.flush();
        task.clearTimer();
        task.endThinking(); // 若流结束时仍处于思考阶段，结算累计耗时
        task.isStreaming = false;
        task.isPaused = false;
        aiMsg.isStreaming = false;
        aiMsg.isPaused = false; // 生成完成，不再显示「继续生成」
        aiMsg.generationStatus = "complete"; // 完整生成（重启后不再显示「继续生成」）
        aiMsg.error = undefined; // 生成成功，清除历史错误信息（错误卡片随之消失）
        /* baseContent（暂停前已生成）+ 本次请求的全文（新增增量，覆盖上面 flush 写入的正文） */
        aiMsg.content = baseContent + fullText;
        /* 请求了联网搜索但整个流中未出现任何搜索事件 → 标记搜索失败（提示已降级） */
        if (task.webSearchEnabled && !task.searchEventSeen) {
          aiMsg.searchFailed = true;
        }
        task.abortHandler = null; // 请求已结束，句柄失效
        this.streamPersistTime.delete(task.aiMsg.id); // 清理节流写库状态
        this.streamTasks.delete(task.aiMsg.id);
        this.syncBackgroundGuardCount(); // 任务数变化，同步保活服务
        this.refreshStreamState(); // 任务已移除 → 当前对话（若为该对话）恢复 idle

        /* 更新 AI 消息完整内容 */
        ConversationRepository.getInstance().updateMessage(aiMsg);
        /**
         * 刷新捕获对话的 updated_at：仅更新时间戳，
         * 避免整体 update 覆盖流式期间侧边栏的重命名/收藏等字段
         * 用完成时刻而非 aiMsg.createdAt（请求发起时刻）：思考较久时 createdAt 偏早，会拉回排序时间
         */
        task.targetConv.updatedAt = Date.now();
        ConversationRepository.getInstance().updateTimestampOnly(task.targetConv.id, task.targetConv.updatedAt);
        /**
         * 首轮 AI 回复完成 → 自动生成对话标题（覆盖截断占位）。
         * 触发条件按"待生成标题的对话 id"匹配（addMessage 首条用户消息时记录），
         * 不依赖"当前对话"：流式期间即使切走，后台流完成后仍为该对话生成标题
         */
        this.maybeGenerateTitle(task);
        /* 页面已销毁：跳过滚动 */
        if (this.isDestroyed) return;
        /* 仅在用户仍停留在原对话时滚动到底部，避免误滚其他对话 */
        if (this.currentConversationId === task.conversationId) {
          this.requestAutoFold(aiMsg); // 思考块折叠请求
          this.scrollToBottom();
        }
      },
      /**
       * 输出达到上限被服务端截断（response.incomplete）：
       * 已生成内容完整保留，但语义上"没走完" → 与暂停一样进入可续写态（气泡显示「继续生成」）
       */
      onIncomplete: (fullText: string, error: LLMError) => {
        task.flush();
        task.clearTimer();
        task.endThinking();
        task.isStreaming = false;
        task.isPaused = true;
        aiMsg.isStreaming = false;
        aiMsg.isSearching = false;
        aiMsg.isPaused = true; // 暂停态 → 气泡右上角显示「继续生成」
        aiMsg.generationStatus = "partial"; // 未走完（进程终止重启后也能识别并恢复）
        aiMsg.error = error; // 结构化错误信息（错误卡片展示错误码/文案/详情）
        aiMsg.content = baseContent + fullText; // 截断前已生成的全部内容
        task.abortHandler = null;
        this.streamPersistTime.delete(task.aiMsg.id);
        /* 任务保留在 streamTasks 表（isPaused=true），「继续生成」直接复用 */
        this.syncBackgroundGuardCount(); // 不再有活跃网络请求，保活计数减一
        this.refreshStreamState();
        /* 持久化已接收内容（继续生成时以此为基础） */
        ConversationRepository.getInstance().updateMessage(aiMsg);
        /* 首轮回复被截断 → 也尝试生成标题（已有内容可为上下文），失败不阻塞流程 */
        this.maybeGenerateTitle(task);
        /* 仅当该对话仍在前台展示时更新 UI 状态并提示（Toast 只显示一句文案，详情在气泡错误卡片） */
        if (this.isDestroyed) return;
        if (this.currentConversationId === task.conversationId) {
          this.requestAutoFold(aiMsg); // 思考块折叠请求
          this.streamState = "paused";
          this.scrollToBottom();
          showToast(getGlobalUiContext(), errorMessageResource(error.code));
        }
      },
      /**
       * 发生错误：不可续写（鉴权/限流/上下文超限等）直接收尾；可续写（网络超时/请求失败/服务端错误等）
       * 按 error.retryable 进入暂停态，保留「继续生成」按钮供用户重试
       */
      onError: (error: LLMError) => {
        task.flush(); // 修复：先合并缓冲增量再清定时器，避免尾部内容丢失
        task.clearTimer();
        task.endThinking(); // 结算当前思考阶段耗时（若有）
        task.isStreaming = false;
        task.isPaused = error.retryable; // 可续写错误 → 任务保留供「继续生成」复用
        aiMsg.isStreaming = false; // 异常结束同样退出流式态
        aiMsg.isSearching = false;
        aiMsg.isPaused = error.retryable; // 可续写错误 → 显示「继续生成」；不可续写 → 不显示
        aiMsg.generationStatus = "partial"; // 未完整生成（重启后仍可「继续生成」）
        aiMsg.error = error; // 结构化错误信息（错误卡片展示错误码/文案/详情）
        task.abortHandler = null;
        this.streamPersistTime.delete(task.aiMsg.id); // 清理节流写库状态
        if (!error.retryable) {
          this.streamTasks.delete(task.aiMsg.id); // 不可续写 → 移除任务
        }
        this.syncBackgroundGuardCount(); // 任务数变化，同步保活服务
        this.refreshStreamState();
        /* 错误消息也入库（含结构化错误信息），方便用户从历史中复盘 */
        ConversationRepository.getInstance().updateMessage(aiMsg);
        /* 首轮回复报错 → 也尝试生成标题（上下文退化为仅用户提问），避免标题永久停留截断占位 */
        this.maybeGenerateTitle(task);
        if (this.isDestroyed) return;
        if (this.currentConversationId === task.conversationId) {
          this.requestAutoFold(aiMsg); // 思考块折叠请求
          if (error.retryable) {
            this.streamState = "paused"; // 可续写错误 → 输入区显示「继续生成」
          }
          this.scrollToBottom();
          showToast(getGlobalUiContext(), errorMessageResource(error.code));
        }
      },
      /**
       * 网络异常中断（连接被掐断等，未收到正常结束事件）→ 进入"暂停"态：
       * 保留已接收内容，任务留在表中，供用户点击「继续生成」从未完成处续写
       */
      onInterrupted: (reason: LLMError) => {
        if (this.isDestroyed) return;
        /**
         * 空回复自动续试：服务端 completed 但无正文（联网搜索后模型空回复）→ 不打断用户，
         * 自动以相同上下文重新生成；连续重试超过上限仍空才落回暂停态提示
         */
        if (reason.code === ErrorCode.EMPTY_ANSWER && task.autoRetryCount < MAX_AUTO_RETRY) {
          this.autoRetryAfterEmpty(task);
          return;
        }
        task.flush(); // 修复：先合并缓冲增量再清定时器，避免尾部内容丢失
        task.clearTimer();
        task.isStreaming = false;
        task.isPaused = true;
        aiMsg.isStreaming = false;
        aiMsg.isSearching = false;
        aiMsg.isPaused = true; // 暂停态 → 气泡操作栏右上角显示「继续生成」
        aiMsg.generationStatus = "partial"; // 未完整生成（进程终止重启后也能识别并恢复）
        aiMsg.error = reason; // 结构化错误信息（错误卡片展示错误码/文案/详情）
        task.endThinking(); // 结算当前思考阶段耗时（若有）
        task.abortHandler = null;
        this.streamPersistTime.delete(task.aiMsg.id); // 清理节流写库状态
        this.syncBackgroundGuardCount(); // 不再有活跃网络请求，保活计数减一
        /* 持久化已接收内容（继续生成时以此为基础） */
        ConversationRepository.getInstance().updateMessage(aiMsg);
        /* 首轮回复被中断 → 也尝试生成标题（已有内容可为上下文），失败不阻塞流程 */
        this.maybeGenerateTitle(task);
        /* 仅当该对话仍在前台展示时更新 UI 状态并提示（Toast 只显示一句文案，详情在气泡错误卡片） */
        if (this.currentConversationId === task.conversationId) {
          this.requestAutoFold(aiMsg); // 思考块折叠请求
          this.streamState = "paused";
          this.scrollToBottom();
          showToast(getGlobalUiContext(), errorMessageResource(reason.code));
        }
      },
    };

    /**
     * 调用 LLM（通过工厂获取 Provider，业务层不依赖具体供应商）
     * 返回值 = 中止句柄，暂停生成时调用（ChatViewModel.pauseStreaming）
     */
    task.abortHandler = LLMProviderFactory.create().sendMessage(context, callbacks, thinkingEffort, webSearch);
  }

  /**
   * 空回复自动重试：completed 但无正文时重新发起请求，用户无感。
   *  - 上下文 = aiMsg 之前的全部消息，不含这条空 AI 消息（模型获得全新一次回答机会）
   *  - 保留已产生的思考过程展示（aiMsg.reasoning 不清空），新一轮思考增量继续追加
   *  - 开关沿用本次请求的设置（深度思考 / 联网搜索），保证风格一致
   */
  private autoRetryAfterEmpty(task: StreamTask): void {
    const aiMsg = task.aiMsg;
    task.autoRetryCount++;
    task.clearTimer();
    task.endThinking(); // 结算上一轮思考耗时
    task.isStreaming = true;
    task.isPaused = false;
    task.searchEventSeen = false; // 新一轮请求，重新判断搜索是否发生
    task.reasoningBuffer = "";
    task.streamBuffer = "";
    task.abortHandler = null; // 旧请求已结束，句柄失效（新一轮 startProviderStream 会重新赋值）
    aiMsg.isStreaming = true;
    aiMsg.isSearching = false;
    aiMsg.searchFailed = false;
    aiMsg.error = undefined; // 重试期间不展示错误卡片
    aiMsg.isPaused = false;
    aiMsg.isThinking = true; // 恢复"思考中"状态
    aiMsg.thinkingStartTime = Date.now();
    /* 修复：仅当任务属于当前对话时才切换输入区状态，避免后台对话的空回复续试污染前台 UI */
    if (task.conversationId === this.currentConversationId) {
      this.streamState = "streaming";
    }
    this.syncBackgroundGuardCount(); // 任务仍在表中，保活计数保持不变
    /* 上下文不含这条空回复消息本身 */
    const context = this.buildContextBefore(aiMsg.id);
    this.startProviderStream(task, context, task.thinkingEffort, task.webSearchEnabled, "");
  }

  /**
   * AI 首次输出内容（思考或正文均算）→ 对话置顶：
   * 更新会话 updatedAt 并写库（侧边栏 onShown 重查即显示最新排序）。
   * 每个流仅置顶一次（timestampUpdated 标记），避免反复写库
   */
  private markConversationActive(task: StreamTask): void {
    if (task.timestampUpdated) return;
    task.timestampUpdated = true;
    task.targetConv.updatedAt = Date.now(); // 输出时刻（思考/正文首次到达时）
    ConversationRepository.getInstance().updateTimestampOnly(task.targetConv.id, task.targetConv.updatedAt);
    /**
     * 历史落点：仅在"当前对话"首次输出内容时持久化激活链（切换变体不写库，落点 = 最后 AI 输出内容的分支）。
     * 后台对话（用户已切走）的流不更新落点：其 DB 落点保持切走前最后输出的分支，避免互相污染
     */
    if (task.conversationId === this.currentConversationId) {
      this.persistActiveChain();
    }
  }

  /**
   * 持久化当前激活链的 is_active 状态（AI 首次输出内容时调用）：
   * 链上消息置 1、链外消息置 0，使 DB 与内存一致，作为打开历史对话时的分支落点
   */
  private persistActiveChain(): void {
    const chainIds = new Set<string>();
    this.messageDataSource.getAll().forEach((m: Message) => {
      chainIds.add(m.id);
    });
    const activeIds: string[] = [];
    this.branchManager.getAll().forEach((m: Message) => {
      if (chainIds.has(m.id)) {
        activeIds.push(m.id);
      }
    });
    /* 修复：先整表熄灭再批量点亮（2 次 UPDATE 替代 N 次独立异步写，缩小进程中断的半一致窗口） */
    ConversationRepository.getInstance().setAllMessagesInactive(this.currentConversationId);
    ConversationRepository.getInstance().updateMessageActiveBatch(activeIds, true);
  }

  /**
   * 暂停当前对话的生成（生成中点击暂停键触发）
   * - 将缓冲区 flush 到消息，保留已生成的全部内容
   * - 中止底层 HTTP 请求（abort 后 Provider 不再触发任何回调，避免残留事件）
   * - 任务保留在 streamTasks 表中（isPaused=true），供「继续生成」复用
   */
  pauseStreaming(): void {
    /* 暂停当前激活链尾的生成任务（多分支下仅作用于当前分支，不干扰其他分支的任务） */
    const task = this.tailTask();
    if (task === undefined || !task.isStreaming || task.isPaused) return;
    /* 1. 合并缓冲区到消息（保留已生成内容）并清除节流定时器 */
    task.flush();
    task.clearTimer();
    /* 2. 中止底层 HTTP 请求 */
    task.abortHandler?.abort();
    task.abortHandler = null;
    this.streamPersistTime.delete(task.aiMsg.id); // 修复：清理节流写库状态
    /* 3. 标记暂停态（任务保留在表中，供继续生成复用） */
    task.isStreaming = false;
    task.isPaused = true;
    task.aiMsg.isStreaming = false;
    task.aiMsg.isSearching = false;
    task.aiMsg.isPaused = true; // 暂停态 → 气泡操作栏右上角显示「继续生成」
    task.aiMsg.generationStatus = "partial"; // 未完整生成（进程终止重启后也能识别并恢复）
    task.endThinking(); // 结算当前思考阶段耗时（若有）
    this.requestAutoFold(task.aiMsg); // 思考块折叠请求
    this.streamState = "paused";
    this.syncBackgroundGuardCount(); // 网络请求已中止，保活计数减一
    /* 4. 持久化已接收内容（继续生成时以此为基础） */
    ConversationRepository.getInstance().updateMessage(task.aiMsg);
    this.scrollToBottom();
  }

  /**
   * 继续生成（点击「继续生成」按钮触发）：
   * 以「历史上下文 + 已生成的部分 AI 消息」重新发起流式请求，模型从未完成处续写。
   * 两种场景：
   *   1. 本会话内暂停（任务仍在 streamTasks 表）→ 复用原 StreamTask（同一 aiMsg / 开关沿用暂停前）
   *   2. 进程被终止后恢复（任务表已清空）→ 链尾是 partial 的 AI 消息 → 重建任务，从未完成处续写
   */
  async resumeStreaming(target?: Message): Promise<void> {
    await this.dbInitPromise;
    if (this.isDestroyed) return;
    /* 点击「继续生成」自动取消编辑状态 */
    this.exitEditMode();
    const convId = this.currentConversationId;
    /**
     * 修复：优先恢复用户点击的那条消息的任务（气泡「继续生成」可能出现在链中任意位置）；
     * 未指定时退回激活链尾任务，多分支下各分支任务独立，互不干扰
     */
    let task: StreamTask | undefined = target !== undefined ? this.streamTasks.get(target.id) : undefined;
    if (task === undefined) {
      task = this.tailTask();
    }
    let aiMsg: Message;
    let thinkingEffort: ThinkingEffort;
    let webSearch: boolean;
    let baseContent: string;
    if (task !== undefined && task.isPaused) {
      /* 场景 1：本分支的暂停任务（同一会话内），复用原开关设置 */
      task.timestampUpdated = false; // 重置置顶标记：继续生成后首次输出正文再次把对话排到最前
      task.autoRetryCount = 0; // 修复：重置空回复自动续试计数，避免历史计数耗尽导致本次无法续试
      aiMsg = task.aiMsg;
      thinkingEffort = task.thinkingEffort;
      webSearch = task.webSearchEnabled;
      /**
       * 修复：覆盖模式（换个回答）在首个增量前被中断时，旧内容尚未清除；
       * 续写后首个增量会清空旧内容，故 baseContent 必须为空，否则 onComplete
       * 按 baseContent+fullText 拼接时会把旧内容重复写回
       */
      baseContent = task.resetOnFirstChunk ? "" : task.aiMsg.content;
    } else {
      /* 链尾有其他活跃流（正在生成中）→ 不满足"继续生成"条件，拒绝恢复 */
      if (task !== undefined && task.isStreaming) return;
      /**
       * 场景 2：进程终止后恢复 —— 链尾存在未完成的 AI 消息则重建任务续写。
       * 修复：指定了目标消息时，仅当它就是链尾那条未完成消息才允许恢复
       * （进程被杀后气泡上的「继续生成」走的就是这条路径），避免误续其他消息
       */
      const restored = this.findLastPartialMessage();
      if (restored === undefined) return;
      if (target !== undefined && target.id !== restored.id) return;
      aiMsg = restored;
      thinkingEffort = this.thinkingEffort;
      webSearch = this.webSearch;
      baseContent = aiMsg.content;
      task = new StreamTask(convId, aiMsg, this.currentConversation);
      task.thinkingEffort = thinkingEffort;
      task.webSearchEnabled = webSearch;
      this.streamTasks.set(task.aiMsg.id, task);
    }
    /* 1. 重置为流式态 */
    task.isPaused = false;
    task.isStreaming = true;
    task.searchEventSeen = false; // 新一轮请求，重新判断搜索是否发生
    aiMsg.isStreaming = true;
    aiMsg.isSearching = false;
    aiMsg.searchFailed = false;
    aiMsg.isPaused = false; // 恢复生成，隐藏气泡上的「继续生成」
    aiMsg.error = undefined; // 重新开始生成，立即清除旧错误卡片
    aiMsg.generationStatus = "partial"; // 续写期间保持未完成标记（防再次中断时丢状态）
    aiMsg.isThinking = true;
    aiMsg.thinkingStartTime = Date.now();
    this.streamState = "streaming";
    this.syncBackgroundGuardCount();
    /* 2. 构造上下文：aiMsg 之前的全部消息 + aiMsg 自身（含已生成的部分内容，模型从此续写） */
    const context = this.buildContextBefore(aiMsg.id);
    /*
     * 占位内容为空（首个 2.5s 内被杀、未产生任何输出）时不把空 AI 消息
     * 塞进上下文，避免向模型发送空 assistant 消息导致续写异常；此时模型重新完整作答
     */
    if (aiMsg.content.length > 0) {
      context.push(aiMsg);
    }
    /* 3. 重新发起请求：baseContent = 暂停前已生成的内容（onComplete 写回时叠加本次增量） */
    this.jumpToBottom();
    this.startProviderStream(task, context, thinkingEffort, webSearch, baseContent);
  }

  /* 依据当前激活链尾的任务状态刷新 UI 状态（任务结束 / 对话切换等场景） */
  private refreshStreamState(): void {
    const task = this.tailTask();
    if (task === undefined) {
      this.streamState = "idle";
    } else if (task.isPaused) {
      this.streamState = "paused";
    } else {
      this.streamState = "streaming";
    }
  }

  /**
   * 按对话 id 收集该对话的全部流任务（key = aiMsg.id，需遍历筛选）
   * 一个对话的不同分支可各自持有暂停/进行中的任务，互不干扰
   */
  private tasksOfConversation(convId: string): StreamTask[] {
    const result: StreamTask[] = [];
    this.streamTasks.forEach((task: StreamTask) => {
      if (task.conversationId === convId) {
        result.push(task);
      }
    });
    return result;
  }

  /* 中止并清理指定对话下的全部流任务（侧边栏删除对话时调用，避免后台流/保活/任务表泄漏） */
  abortTasksOfConversations(convIds: string[]): void {
    let cleared = false;
    this.streamTasks.forEach((task: StreamTask, id: string) => {
      if (convIds.indexOf(task.conversationId) >= 0) {
        task.clearTimer();
        task.abortHandler?.abort();
        task.abortHandler = null;
        task.isStreaming = false;
        task.isPaused = false;
        this.streamPersistTime.delete(id);
        this.streamTasks.delete(id);
        cleared = true;
      }
    });
    if (cleared) {
      this.syncBackgroundGuardCount();
      this.refreshStreamState();
    }
  }

  /**
   * 获取当前对话对应的流任务（pause / resume / streamState 判定统一入口）
   * 1. 优先取激活链尾消息的任务（正常生成/暂停场景，流式消息位于链尾）
   * 2. 兜底：链尾无任务时（切换分支后流式/暂停任务挂在非激活变体上，
   *    已脱离激活链尾），取当前对话中仍在生成（isStreaming）的任务；
   *    无进行中任务则取暂停态任务。保证切换分支后暂停/继续生成仍可作用
   *    于正在运行的生成，而不是静默失效。
   */
  private tailTask(): StreamTask | undefined {
    const list = this.messageDataSource.getAll();
    if (list.length > 0) {
      const tail = this.streamTasks.get(list[list.length - 1].id);
      if (tail !== undefined) return tail;
    }
    /* 兜底：遍历当前对话的任务表，优先流式中任务，其次暂停态任务 */
    let pausedTask: StreamTask | undefined = undefined;
    this.streamTasks.forEach((task: StreamTask) => {
      if (task.conversationId !== this.currentConversationId) return;
      if (task.isStreaming) {
        pausedTask = task; // 流式任务优先
        return;
      }
      if (task.isPaused && pausedTask === undefined) {
        pausedTask = task;
      }
    });
    return pausedTask;
  }

  /**
   * 恢复"进程被终止/中断"的未完成 AI 消息（加载对话时调用）：
   * 激活链尾是未完成(partial)的 AI 消息 → 置 isPaused=true，气泡显示「继续生成」
   * 不再要求 content 非空——进程在首个 2.5s 节流落库前被杀时，
   * 占位消息只有状态、没有内容，若仍要求 content>0 则永远无法恢复；
   * 不可重试的错误（鉴权/限流/请求非法）由 error.retryable=false 排除，不显示「继续生成」
   */
  private restoreInterruptedMessage(chain: Message[]): void {
    if (chain.length === 0) return;
    const tail = chain[chain.length - 1];
    if (!tail.isUser() && tail.generationStatus === "partial"
      && (tail.error === undefined || tail.error.retryable)) {
      tail.isPaused = true;
    }
  }

  /**
   * 查找当前对话链尾"未完成生成"的 AI 消息（进程终止后恢复续写用）
   * partial 且可续写即返回（不要求 content 非空）
   */
  private findLastPartialMessage(): Message | undefined {
    const list = this.messageDataSource.getAll();
    if (list.length === 0) return undefined;
    const tail = list[list.length - 1];
    if (tail.isUser() || tail.generationStatus !== "partial") {
      return undefined;
    }
    if (tail.error !== undefined && !tail.error.retryable) {
      return undefined; // 不可重试错误：不提供续写
    }
    return tail;
  }

  /**
   * 添加消息到激活链列表并持久化（普通发送场景）
   * 自动设置分支链字段：parentId / branchGroupId(=parentId) / variantIndex(组内递增) / isActive
   * @param role 消息角色
   * @param content 消息正文
   * @param parentId 父消息 id（分支链锚点；根用户消息传 ""）
   * @param images 图片附件列表（仅用户消息有值；默认空）
   * @param files 文件附件列表（仅用户消息有值；默认空）
   */
  private addMessage(role: "user" | "assistant", content: string, parentId: string, images: ImageAttachment[] = [], files: FileAttachment[] = []): Message {
    const msg = new Message(this.currentConversationId, role, content);
    msg.images = images;
    msg.files = files;
    /**
     * 修复(partial 占位)：AI 占位消息必须以 partial 状态入库——若进程在首个 2.5s 节流落库前被杀，
     * DB 里 complete 的空消息无法被恢复逻辑识别为「可继续生成」
     */
    if (role === "assistant") {
      msg.generationStatus = "partial";
    }
    msg.parentId = parentId;
    msg.branchGroupId = parentId; // 分支组锚点 = 父消息 id（同父消息互为变体）
    msg.variantIndex = this.branchManager.nextVariantIndex(parentId); // 组内变体序号递增
    msg.isActive = true;
    this.branchManager.add(msg);
    this.messageDataSource.push(msg);
    /* 新消息即链尾：同步「换个回答」标记（新增消息后新最后一条的显隐即时生效） */
    this.lastMessageId = msg.id;
    /**
     * 修复(激活链一致性)：存在未落库的分支切换时，先把当前激活链固化进 DB 再插新消息，
     * 保证「发送落库」与「激活链落库」顺序一致；即使随后生成失败/被杀，链也不分裂
     */
    if (this.pendingActiveChainPersist) {
      this.pendingActiveChainPersist = false;
      this.persistActiveChain();
    }
    if (this.currentConversationId) {
      /**
       * 首条用户消息 → 对话真正开始，此时才将对话入库并生成标题
       * （延迟入库：确保空白对话不会出现在历史记录中）
       */
      if (role === "user" && this.isFirstUserMsg) {
        this.isFirstUserMsg = false;
        /* 记录待生成标题的对话：首轮 AI 回复完成后（onComplete）触发标题生成并清空 */
        this.pendingTitleConvId = this.currentConversationId;
        /* 标题占位：正文优先（截断）；纯图片/纯文件消息用占位，避免空标题 */
        this.currentConversation.title =
          content.length > 0
            ? (content.length > MAX_TITLE_LENGTH ? content.substring(0, MAX_TITLE_LENGTH) + "..." : content)
            : (images.length > 0 ? "[图片]" : (files.length > 0 ? "[文件]" : ""));
        this.currentConversation.updatedAt = msg.createdAt;
        ConversationRepository.getInstance().insert(this.currentConversation);
      }
      ConversationRepository.getInstance().insertMessage(msg);
    }
    return msg;
  }

  /**
   * 创建消息并持久化但不入列（分支变体创建场景）
   * 与 addMessage 的唯一区别：不入激活列表，由后续 rebuildActiveChain 统一重建入列
   */
  private createAndPersist(role: "user" | "assistant", content: string, parentId: string, images: ImageAttachment[] = [], files: FileAttachment[] = []): Message {
    const msg = new Message(this.currentConversationId, role, content);
    msg.images = images;
    msg.files = files;
    /* 修复(partial 占位)：AI 占位消息以 partial 状态入库，避免空内容被误判为已完成的完整回复 */
    if (role === "assistant") {
      msg.generationStatus = "partial";
    }
    msg.parentId = parentId;
    msg.branchGroupId = parentId;
    msg.variantIndex = this.branchManager.nextVariantIndex(parentId);
    msg.isActive = true;
    this.branchManager.add(msg);
    if (this.currentConversationId) {
      ConversationRepository.getInstance().insertMessage(msg);
    }
    return msg;
  }

  /* ===== 重新生成 / 新建分支 / 编辑 / 切换分支（对话分支核心） ===== */

  /* AI 消息「换个回答」：直接覆盖当前回复内容重新生成（不产生新变体） */
  async regenerateMessage(aiMsg: Message): Promise<void> {
    await this.dbInitPromise;
    if (this.isDestroyed) return;
    const sendConvId = this.currentConversationId;
    if (this.isStreamingFor(sendConvId)) {
      showToast(getGlobalUiContext(), $r("app.string.streaming_busy"));
      return;
    }
    if (aiMsg.isUser()) return; // 仅 AI 消息支持重新生成
    /* 编辑态下点击「换个回答」→ 自动取消编辑状态（清空 editingMessageId/prefill，输入框联动恢复） */
    this.exitEditMode();
    /* 覆盖前清空旧内容，进入流式态 */
    aiMsg.content = "";
    aiMsg.reasoning = "";
    aiMsg.searchFailed = false;
    aiMsg.error = undefined; // 重新开始生成，立即清除旧错误卡片
    aiMsg.isPaused = false; // 重置暂停态（防止残留「继续生成」按钮与流式态并存）
    aiMsg.isThinking = true;
    aiMsg.isStreaming = true;
    aiMsg.thinkingStartTime = Date.now();
    /* 上下文 = 激活链中该消息之前的部分；搜索词 = 对应的用户提问 */
    const context = this.buildContextBefore(aiMsg.id);
    const prompt = this.branchManager.findPromptOf(aiMsg);
    const targetConv = this.currentConversation;
    /* 使用当前输入区开关状态（而非上次发送时的值） */
    await this.startStreamReply(sendConvId, targetConv, aiMsg, context,
      this.webSearch, this.thinkingEffort, prompt, true);
  }

  /* AI 消息「生成新回复」：保留旧回复，创建新变体并重新生成（旧分支整条熄灭，可切回） */
  async createBranch(aiMsg: Message): Promise<void> {
    await this.dbInitPromise;
    if (this.isDestroyed) return;
    const sendConvId = this.currentConversationId;
    if (this.isStreamingFor(sendConvId)) {
      showToast(getGlobalUiContext(), $r("app.string.streaming_busy"));
      return;
    }
    if (aiMsg.isUser()) return; // 仅 AI 消息支持新建分支
    /* 编辑态下点击「生成新回复」→ 同样自动取消编辑状态（与重新生成语义一致） */
    this.exitEditMode();
    /* 1. 创建新变体（与旧回复同父、同分支组、序号 +1），先进入流式态 */
    const newVariant = this.createAndPersist("assistant", "", aiMsg.parentId);
    newVariant.isThinking = true;
    newVariant.isStreaming = true;
    newVariant.thinkingStartTime = Date.now();
    /* 2. 熄灭旧分支（旧回复及其后续链），保留在数据库中供切换查看 */
    this.branchManager.deactivateBranchFrom(aiMsg);
    /* 3. 重建激活链（新变体成为链尾） */
    await this.rebuildActiveChain(newVariant.id);
    /* 4. 构造上下文并发起流式回复 */
    const context = this.buildContextBefore(newVariant.id);
    const prompt = this.branchManager.findPromptOf(newVariant);
    const targetConv = this.currentConversation;
    /* 使用当前输入区开关状态（而非上次发送时的值） */
    await this.startStreamReply(sendConvId, targetConv, newVariant, context,
      this.webSearch, this.thinkingEffort, prompt);
  }

  /**
   * 编辑用户消息（隐含创建新分支）：
   * 在目标用户消息处创建新变体（保留原内容为旧分支），并重新生成 AI 回复
   */
  private async editUserMessage(
    editTargetId: string,
    newText: string,
    webSearch: boolean,
    thinkingEffort: ThinkingEffort,
    images: ImageAttachment[] = [],
    files: FileAttachment[] = [],
  ): Promise<void> {
    const sendConvId = this.currentConversationId;
    const target = this.branchManager.getById(editTargetId);
    if (target === undefined || !target.isUser()) return; // 目标必须是用户消息
    /* 编辑路径的视觉/文件校验延迟到占位创建后的解析阶段（见下方步骤 5/6）：
       编辑回填的文件可能未解析（新增文件），需先解析再判定 pageImages */
    if (this.isStreamingFor(sendConvId)) {
      showToast(getGlobalUiContext(), $r("app.string.streaming_busy"));
      return;
    }
    /* 1. 创建新用户消息变体（同父、同分支组、序号 +1；用编辑后的图片、文件与文本） */
    const newUserMsg = this.createAndPersist("user", newText, target.parentId, images, files);
    /* 1.1 编辑的是首轮提问 → 对话主题可能改变：
     *     - 标题仍是占位（未被侧边栏手动重命名/AI 正式标题覆盖）时，同步为新的提问截断占位
     *     - 重置待生成标记，让新首轮回复完成时重新生成正式标题（正式/手动标题由生成流程的占位校验保护） */
    const chainFirst = this.branchManager.getAll()
      .filter((m: Message) => m.conversationId === sendConvId && m.isActive)
      .sort((a: Message, b: Message) => a.createdAt - b.createdAt)
      .find((m: Message) => m.isUser());
    if (chainFirst !== undefined && chainFirst.id === target.id) {
      const freshConv = await ConversationRepository.getInstance().getById(sendConvId);
      if (freshConv !== undefined && freshConv.title === this.currentConversation.title) {
        /* 标题占位：正文优先（截断）；纯图片/纯文件消息用占位，避免空标题 */
        this.currentConversation.title =
          newText.length > 0
            ? (newText.length > MAX_TITLE_LENGTH ? newText.substring(0, MAX_TITLE_LENGTH) + "..." : newText)
            : (images.length > 0 ? "[图片]" : (files.length > 0 ? "[文件]" : ""));
        ConversationRepository.getInstance().update(this.currentConversation);
      }
      /* 仅未被用户命名的对话才重置待生成标记（用户命名过 → 不再自动生成 AI 标题） */
      if (freshConv === undefined || !freshConv.isUserNamed) {
        this.pendingTitleConvId = sendConvId; // 重置待生成标记
        this.titleAttempts.delete(sendConvId); // 重置重试计数（全新提问，重新计数）
      }
    }
    /* 2. 熄灭旧用户消息及其后续链 */
    this.branchManager.deactivateBranchFrom(target);
    /* 3. 重建激活链（新用户消息成为链尾） */
    await this.rebuildActiveChain(newUserMsg.id);
    /* 4. 创建 AI 占位（parent = 新用户消息）并入列。
       先进入「文件解析中」状态（isParsing=true）：编辑新增/更换的文件需要先解析再生成 */
    const aiMsg = this.createAndPersist("assistant", "", newUserMsg.id);
    aiMsg.isStreaming = true;
    if (files.length > 0) {
      aiMsg.isParsing = true;
    }
    this.reloadActiveList();

    /* 5. 延迟解析：编辑回填的文件可能未解析（新增文件），先逐文件解析；
       失败 → AI 占位保留并转为错误卡片（不删除分支），其余流程终止 */
    if (files.length > 0) {
      try {
        for (const f of files) {
          await FileParser.getInstance().parseForSend(f);
        }
      } catch (e) {
        aiMsg.isParsing = false;
        aiMsg.isStreaming = false;
        aiMsg.error = buildError(ErrorCode.FILE_PARSE_FAILED, (e as Error).message, undefined, "local");
        return;
      }
    }

    /* 6. 解析后重算视觉：图片与「无文本兜底」的页面图（pdf）走视觉模型；
       docx/pptx 双通道（文本+排版图）皆可用，非视觉模型下不拦截。
       不通过 → AI 占位转为错误卡片（保留新分支） */
    const hasVisual: boolean = images.length > 0
      || files.some((f: FileAttachment) => f.pageImages.length > 0 && f.textContent.length === 0);
    if (hasVisual && !isVisionModel(AppConfig.getInstance().getModel())) {
      aiMsg.isParsing = false;
      aiMsg.isStreaming = false;
      aiMsg.error = buildError(ErrorCode.FILE_PARSE_FAILED, "当前模型不支持解析PDF文件，请切换模型后重试", undefined, "local");
      return;
    }

    /* 7. 解析完成 → 转为思考态，构造上下文并发起流式回复。
       解析结果修改发生在 createAndPersist 之后，须补写落库（保证重启后文件内容可恢复） */
    aiMsg.isParsing = false;
    aiMsg.isThinking = true;
    aiMsg.thinkingStartTime = Date.now();
    if (files.length > 0) {
      ConversationRepository.getInstance().updateMessage(newUserMsg);
    }
    const context = this.buildContextBefore(aiMsg.id);
    const targetConv = this.currentConversation;
    await this.startStreamReply(sendConvId, targetConv, aiMsg, context, webSearch, thinkingEffort, newText);
  }

  /* 用户消息「编辑」：进入编辑态（内容+图片+文件回填输入框），发送时创建新分支 */
  startEdit(msg: Message): void {
    if (msg.isStreaming) return; // 流式中不可编辑
    /* 方式 B：纯文本模型下禁止编辑带图/带 pdf 消息（无法新增/保留，直接拒绝进入编辑态）；
       视觉模型下可自由增删改图片/pdf（编辑发送路径由 handleUserSend 二次校验）。
       docx/pptx 有文本兜底（pageImages 与 textContent 并存），纯文本模型下可正常编辑（仅发文本）；
       txt/md 文件走文本通道，纯文本模型下可正常编辑 */
    const hasVisual: boolean = msg.images.length > 0
      || msg.files.some((f: FileAttachment) => f.pageImages.length > 0 && f.textContent.length === 0);
    if (hasVisual && !isVisionModel(AppConfig.getInstance().getModel())) {
      showToast(getGlobalUiContext(), $r("app.string.vision_required"));
      return;
    }
    this.resetScrollFollow(); // 进入编辑态 → 恢复自动跟随（用户即将输入/阅读输入区）
    this.editingMessageId = msg.id;
    this.editingPrefill = msg.content;
    this.editingPrefillImages = msg.images;
    this.editingPrefillFiles = msg.files;
  }

  /**
   * 编辑态对齐（仅由 ChatPage 键盘弹出防抖回调触发，见 ChatPage.keyboardHeightChange）：
   * 键盘稳定后（RESIZE 压缩视口完成）平滑滚动，使被编辑消息的底部（ListItem 尾部）
   * 与列表视口底部对齐。List 占据标题栏与 ChatInput 之间的全部剩余空间 → 视口底部
   * 即输入区顶部，用户可边看原消息边在输入框修改。
   * ScrollAlign.END = item 尾部与视口尾部对齐；smooth=true 平滑滚动。
   * 对齐后不在底部 → setAtBottom(false) 取消自动跟随，避免后续钉底逻辑把视口拉回
   */
  scrollToEditTarget(): void {
    const targetId = this.editingMessageId;
    if (targetId.length === 0) {
      return; // 非编辑态（或编辑已取消）：无对齐目标
    }
    const list = this.messageDataSource.getAll();
    const idx = list.findIndex((m: Message) => m.id === targetId);
    if (idx < 0) {
      return; // 目标不在激活链上（异常场景）：无法对齐，保持当前位置
    }
    this.setAtBottom(false); // 编辑对齐后不再处于底部，取消自动跟随
    /* 可调偏移（vp）：正值越大消息越贴输入区（更靠下）。调这个值即可改对齐高度 */
    const editAlignBottomVp: number = 42;
    try {
      /* 无动画定位到消息尾部（END），避免与下面 scrollBy 的平滑动画竞争抖动 */
      this.listScroller.scrollToIndex(idx, false, ScrollAlign.END);
    } catch (e) {
      /* 个别版本滚动异常：回退为无动画滚动到消息顶部，至少保证消息可见 */
      this.listScroller.scrollToIndex(idx, false, ScrollAlign.START);
    }
    /* 再向上回滚 editAlignBottomVp：让消息相对更靠下（贴近输入区），微调对齐位置 */
    if (this.scrollAnimator !== undefined) {
      this.scrollAnimator(() => {
        this.listScroller.scrollBy(0, -editAlignBottomVp);
      });
    } else {
      this.listScroller.scrollBy(0, -editAlignBottomVp);
    }
  }

  /* 退出编辑态（编辑发送完成 / 切换对话时调用） */
  exitEditMode(): void {
    this.editingMessageId = "";
    this.editingPrefill = "";
    this.editingPrefillImages = [];
    this.editingPrefillFiles = [];
  }

  /* 切换分支：在当前消息的分支组内按 delta(±1) 切换变体，并整条链重建 */
  switchBranch(msg: Message, delta: number): void {
    if (msg.isStreaming) return; // 流式中不可切换
    const group = this.branchManager.getAll().filter(m => m.branchGroupId === msg.branchGroupId);
    if (group.length <= 1) return; // 只有一个变体，无需切换
    group.sort((a, b) => a.variantIndex - b.variantIndex);
    const curPos = group.findIndex(m => m.id === msg.id);
    const total = group.length;
    /* 循环切换：支持跨 0 → total-1 与 total-1 → 0 */
    const target = group[(((curPos + delta) % total) + total) % total];
    /**
     * 传入 scrollToTargetId（目标变体）与 fromId（切换前的当前消息）：
     * 两者是"同位置兄弟"，替换数据前先滚到旧消息位置锁定区域，避免替换后闪烁
     * persist=false：切换变体只是浏览/激活内存链，不改变 DB 中"最后 AI 输出分支"的历史落点
     */
    this.rebuildActiveChain(target.id, target.id, msg.id, false);
    /* 纯浏览切换只改内存不落库 → 置脏标记；下次发送前先固化，避免失败/被杀时双激活链 */
    this.pendingActiveChainPersist = true;
  }

  /**
   * 删除消息及其后续所有分支（子树整体删除）
   * - 从 DB 批量删除（消息 id 集合）
   * - 从分支链管理器的消息缓存移除
   * - 若该消息正在流式输出，先中止对应流任务
   * - 列表重建；全部删空则重置为新对话（同步删除已无内容的对话记录）
   */
  async deleteMessage(msg: Message): Promise<void> {
    await this.dbInitPromise;
    if (this.isDestroyed) return;
    const convId = this.currentConversationId;
    if (convId.length === 0) return; // 空白新对话尚未入库，无可删除

    /* 编辑中的用户消息不可删除：其内容正回填在输入框中，删除会破坏"编辑 → 新建分支"的锚点 */
    if (msg.id === this.editingMessageId) {
      showToast(getGlobalUiContext(), $r('app.string.edit_delete_forbidden'));
      return;
    }

    /* 2. 收集子树 id 集合：该消息 + 所有后代（含各变体分支），沿 parentId 广度遍历 */
    const deleteIds: string[] = [];
    const stack: string[] = [msg.id];
    while (stack.length > 0) {
      const curId = stack.pop();
      if (curId === undefined) continue;
      if (deleteIds.indexOf(curId) >= 0) continue; // 防重复
      deleteIds.push(curId);
      this.branchManager.getAll().forEach((m: Message) => {
        if (m.parentId === curId) {
          stack.push(m.id);
        }
      });
    }

    /* 2.5 清理子树内所有消息对应的流任务（含其他分支暂停/生成中的任务），按消息 id 精确清理 */
    let clearedTask = false;
    deleteIds.forEach((id: string) => {
      const t = this.streamTasks.get(id);
      if (t !== undefined) {
        t.clearTimer();
        t.abortHandler?.abort(); // 中止底层 HTTP 请求（若仍在生成中）
        t.abortHandler = null;
        t.isStreaming = false;
        t.isPaused = false;
        if (t.aiMsg.id === msg.id) {
          /* 被删消息自身若正在生成，清除其 UI 流式态 */
          t.aiMsg.isStreaming = false;
          t.aiMsg.isPaused = false;
        }
        this.streamPersistTime.delete(id); // 清理节流写库状态
        this.streamTasks.delete(id);
        clearedTask = true;
      }
    });
    if (clearedTask) {
      this.syncBackgroundGuardCount();
      this.refreshStreamState();
    }

    /* 3. 持久化：删除消息子树；随后按 DB 真实剩余条数判断对话是否已空，若空则连同对话一并删除（单事务原子）。
       统一走 deleteMessagesAndConversationIfEmpty（内部 countByConversation 判定），
       不再依赖「子树 == 缓存全量」的启发式条件：多根树/流式占位未落库/陈旧缓存等
       缓存与 DB 失配场景下，该条件会误判为"未删空"，导致空对话记录残留侧边栏 */
    await ConversationRepository.getInstance().deleteMessagesAndConversationIfEmpty(convId, deleteIds);

    /* 4. 更新内存缓存并重建列表 */
    this.branchManager.removeMany(deleteIds);
    if (this.branchManager.size() === 0) {
      this.newConversation(); // 删空 → 回到新对话状态
    } else {
      /* 删除的是当前激活的变体且有剩余兄弟 → 激活"紧邻前一个变体"（6/8 删除后跳到 5/7，而非回到第一个） */
      const prevSibling = this.branchManager.findPrevSiblingForDeleted(msg);
      if (prevSibling !== undefined) {
        /* 复用切换分支的锚点路径（scrollToTargetId + fromId）：删除后的回退与切换分支效果一致 */
        await this.rebuildActiveChain(prevSibling.id, prevSibling.id, msg.id, true);
      } else {
        this.reloadActiveList();
      }
    }
  }

  /**
   * 重建激活链（切换分支核心）：
   * 1. 全量熄灭 → 2. 点亮目标变体的祖先路径 → 3. 点亮目标变体的后续链
   * 4. 持久化激活状态 → 5. 重载列表 → 6.（可选）滚动到目标消息底部
   * @param targetId 点亮的目标变体 id
   * @param scrollToTargetId 可选：重载后滚动到该消息，使其操作栏与列表底部对齐（切换分支用）
   * @param fromId 可选：切换前的当前消息 id（与目标变体同位置兄弟，用于替换数据前锁定滚动区域）
   * @param persist 是否持久化激活链（切换变体 = 纯浏览置 false，不改变历史落点；新建分支/编辑 = 产生新内容置 true）
   */
  private async rebuildActiveChain(targetId: string, scrollToTargetId?: string, fromId?: string,
    persist: boolean = true): Promise<void> {
    const convId = this.currentConversationId;
    /* 1. 全部熄灭（内存；切换变体时不清 DB，保持"最后 AI 输出分支"的历史落点） */
    this.branchManager.getAll().forEach((m: Message) => {
      m.isActive = false;
    });
    if (persist) {
      this.pendingActiveChainPersist = false; // 本次重建已落库，清除脏标记
      ConversationRepository.getInstance().setAllMessagesInactive(convId);
    }

    /* 2. 祖先路径：目标变体 → parent → … → 根 */
    /**
     * 注意：ArkTS 不支持 while 条件对循环体内被重新赋值的变量做类型收窄，
     * 故统一用 string 游标 + 循环内 const 捕获 + 显式判空，保证编译通过
     */
    const byId = new Map<string, Message>();
    this.branchManager.getAll().forEach(m => byId.set(m.id, m));
    const activeIds: string[] = [];
    let curId: string = targetId;
    while (true) {
      const node = byId.get(curId);
      if (node === undefined) break; // 目标/祖先必然存在，兜底退出
      node.isActive = true;
      activeIds.push(node.id);
      if (node.parentId.length === 0) break; // 已到根
      curId = node.parentId;
    }

    /* 3. 后续链：沿激活子节点延伸（无激活则取组内最早变体，保证旧分支可完整恢复） */
    curId = targetId;
    while (true) {
      const node = byId.get(curId);
      if (node === undefined) break;
      const children = this.branchManager.getAll().filter(m => m.parentId === node.id);
      if (children.length === 0) break;
      const next = this.branchManager.selectNextChild(children);
      if (next === undefined) break;
      next.isActive = true;
      activeIds.push(next.id);
      curId = next.id;
    }

    /* 4. 持久化激活状态（逐个 UPDATE，激活链消息量有限，性能可接受；切换变体跳过） */
    if (persist) {
      activeIds.forEach(id => {
        ConversationRepository.getInstance().updateMessageActive(id, true);
      });
    }

    /* 5. 重载激活链列表 */
    const chain = this.branchManager.buildActiveChain();

    if (scrollToTargetId !== undefined && scrollToTargetId.length > 0) {
      /**
       * 5.1 切换分支（记录锚点 → 增量替换 → 恢复偏移）：
       *   目标变体与旧消息是同 index 兄弟（前缀相同、contentY 相同），
       *   只需在切换前偏移上补偿两者高度差，即可让操作栏（消息底部）保持原位
       */
      const oldList = this.messageDataSource.getAll();
      const oldIdx = oldList.findIndex(m => m.id === fromId);
      let baseOffset = -1; // -1 = 未记录（旧消息未渲染/异常），回退贴底
      let baseHeight = -1;
      if (oldIdx >= 0) {
        try {
          baseOffset = Number(this.listScroller.currentOffset().yOffset);
          baseHeight = Number(this.listScroller.getItemRect(oldIdx).height);
        } catch (e) {
          baseOffset = -1;
          baseHeight = -1;
        }
      }

      /* 增量替换：只更新变化的后缀，前缀 ListItem 复用（避免 onDataReloaded 全量重建 + Markdown 重渲染） */
      let prefixLen = 0;
      const minLen = Math.min(oldList.length, chain.length);
      while (prefixLen < minLen && oldList[prefixLen].id === chain[prefixLen].id) {
        prefixLen++;
      }
      /* 兜底：旧链非空但完全无公共前缀（异常场景）→ 退回全量重载 */
      if (oldList.length > 0 && prefixLen === 0) {
        this.messageDataSource.replaceAll(chain);
      } else {
        this.messageDataSource.replaceRange(prefixLen, oldList.length - prefixLen, chain.slice(prefixLen));
      }
      /* 分支切换/删除回退后链尾可能变化：同步「换个回答」标记（replaceRange 前缀复用 item，必须数据驱动刷新） */
      this.syncLastMessageId();

      /**
       * 锚点恢复期间抑制 onListItemHeightChanged 的自动钉底，
       * 避免新变体渲染增高触发 scrollToBottom 打断锚点恢复
       */
      this.isRestoringAnchor = true;
      /**
       * 锚点静默期：从切换开始到补偿完成后的一段时间内，抑制所有自动钉底。
       * 补偿滚动可能触发 onReachEnd（会清除 isUserOperating），而新变体 Markdown 异步渲染
       * 增高又会走 onListItemHeightChanged → scrollToBottom，导致"切换后跳到底部"
       */
      this.anchorSuppressUntil = Date.now() + ANCHOR_SUPPRESS_MS;

      /* 立即恢复到切换前偏移，消除数据替换可能引起的回弹/闪跳（失败忽略，setTimeout 兜底） */
      if (baseOffset >= 0) {
        try {
          this.listScroller.scrollTo({ xOffset: 0, yOffset: baseOffset });
        } catch (e) {
          /* 忽略，交给下面的 setTimeout 兜底 */
        }
      }

      /* 5.2 等新变体渲染出高度后，按高度差微调，让操作栏精确回到切换前位置 */
      setTimeout(() => {
        if (baseOffset >= 0 && baseHeight > 0) {
          this.scrollMessageToAnchor(scrollToTargetId, baseOffset, baseHeight);
        } else {
          /* 锚点未记录（异常）：保持当前偏移不滚动，避免回退贴底造成页面混乱 */
          this.isRestoringAnchor = false;
        }
      }, 50);
    } else {
      /* 非切换分支（新建分支/编辑等）：直接替换 + 滚到底部 */
      this.messageDataSource.replaceAll(chain);
      this.syncLastMessageId();
      this.scrollToBottom();
    }
  }

  /**
   * 切换分支后按"高度差"恢复操作栏位置（不依赖 getItemRect 的 y 坐标语义）：
   * 目标变体与旧消息是同 index 兄弟（前缀相同、contentY 相同），
   * 只需在切换前的内容偏移 baseOffset 上补偿两者高度差，即可让操作栏（消息底部）保持原位
   * @param messageId 目标消息 id（切换后的新变体）
   * @param baseOffset 切换前的内容滚动偏移（currentOffset().yOffset）
   * @param baseHeight 切换前旧消息的高度（getItemRect().height）
   */
  private scrollMessageToAnchor(messageId: string, baseOffset: number, baseHeight: number, retryCount: number = 0,
    lastHeight: number = -1, stableCount: number = 0): void {
    const list = this.messageDataSource.getAll();
    const idx = list.findIndex(m => m.id === messageId);
    if (idx < 0) {
      /* 目标不在激活链上（异常，理论上不会发生）：无法定位，保持当前位置 */
      this.isRestoringAnchor = false;
      return;
    }
    try {
      /* 新变体高度（getItemRect 对部分可见的 item 也返回完整布局高度） */
      const newHeight = Number(this.listScroller.getItemRect(idx).height);
      if (newHeight <= 0) {
        /**
         * item 尚未完成布局（getItemRect 返回 0）：延迟重试，等待布局完成后再检测。
         * 上限放宽到约 10s（200 次 × 50ms），超时放弃补偿（保持原位）
         */
        if (retryCount < 200) {
          setTimeout(() => {
            this.scrollMessageToAnchor(messageId, baseOffset, baseHeight, retryCount + 1);
          }, 50);
        } else {
          this.isRestoringAnchor = false;
        }
        return;
      }
      /**
       * 高度稳定检测：Markdown 异步渲染分多次增高（图片/代码块/表格），初始布局高度（如 181）
       * 远小于最终高度（如 4750）。必须等连续多次测量值一致才补偿，否则 newOffset 基于错误高度计算
       */
      const isStable = lastHeight >= 0 && Math.abs(newHeight - lastHeight) < 0.5;
      const newStable = isStable ? stableCount + 1 : 0;
      if (newStable < 2) {
        if (retryCount < 200) {
          /* 高度仍在变化：继续轮询（记录本次高度与稳定计数） */
          setTimeout(() => {
            this.scrollMessageToAnchor(messageId, baseOffset, baseHeight, retryCount + 1, newHeight, newStable);
          }, 50);
        } else {
          /* 持续变化超过 10s：按当前高度补偿，避免永久等待 */
          this.compensateAnchor(messageId, baseOffset, baseHeight, newHeight);
        }
        return;
      }
      /* 高度稳定：执行高度差补偿，让切换后消息底部（操作栏）回到切换前的屏幕位置 */
      this.compensateAnchor(messageId, baseOffset, baseHeight, newHeight);
    } catch (e) {
      if (retryCount < 200) {
        setTimeout(() => {
          this.scrollMessageToAnchor(messageId, baseOffset, baseHeight, retryCount + 1, lastHeight, stableCount);
        }, 50);
      } else {
        /* getItemRect 持续失败（item 始终未渲染等）：保持当前位置，不回退贴底 */
        this.isRestoringAnchor = false;
      }
    }
  }

  /* 执行高度差补偿滚动（操作栏回到切换前屏幕位置），并续期锚点静默期 */
  private compensateAnchor(messageId: string, baseOffset: number, baseHeight: number, newHeight: number): void {
    const newOffset = baseOffset + (newHeight - baseHeight);
    try {
      /* 绝对偏移滚动（xOffset 保持不变，本列表仅垂直滚动） */
      this.listScroller.scrollTo({ xOffset: 0, yOffset: newOffset });
    } catch (e) {
      /* 忽略，保持当前位置 */
    }
    this.isRestoringAnchor = false;
    /* 补偿完成后续期静默期：本次补偿滚动可能触发 onReachEnd，且新变体 Markdown 仍在异步渲染 */
    this.anchorSuppressUntil = Date.now() + ANCHOR_SUPPRESS_MS;
  }

  /* 构造某消息之前的激活上下文（不含该消息本身），用于重新生成/新建分支 */
  private buildContextBefore(targetId: string): Message[] {
    const list = this.messageDataSource.getAll();
    const idx = list.findIndex(m => m.id === targetId);
    if (idx < 0) return list;
    return list.slice(0, idx);
  }

  /* 从被浏览页面的完整 URL 提取域名（去掉协议/路径/查询/锚点与追踪尾巴，用于"正在浏览 xxx 域名"展示） */
  private extractDomain(url: string): string {
    let u = url;
    const hashIdx = u.indexOf('#');
    if (hashIdx >= 0) u = u.substring(0, hashIdx);
    const qIdx = u.indexOf('?');
    if (qIdx >= 0) u = u.substring(0, qIdx);
    const protoIdx = u.indexOf('://');
    if (protoIdx >= 0) u = u.substring(protoIdx + 3);
    const pathIdx = u.indexOf('/');
    if (pathIdx >= 0) u = u.substring(0, pathIdx);
    const portIdx = u.indexOf(':');
    if (portIdx >= 0) u = u.substring(0, portIdx);
    if (u.startsWith('www.')) u = u.substring(4);
    return u.length > 0 ? u : url;
  }

  /* 依据分支链管理器中消息的 isActive 状态重建列表（激活链）并钉到底部 */
  private reloadActiveList(): void {
    const chain = this.branchManager.buildActiveChain();
    this.messageDataSource.replaceAll(chain);
    this.syncLastMessageId();
    this.scrollToBottom();
  }

  /**
   * 同步激活链最后一条消息 id（驱动「换个回答」显隐）。
   * 在激活链结构性变化的所有出口调用（加载/新增/删除/分支切换/重载/新建对话）：
   * 取数据源链尾 id，@Trace 变化驱动 ChatPage build 重跑 → item @Param 刷新。
   * 空列表置空串（无消息，无最后一条）
   */
  private syncLastMessageId(): void {
    const list = this.messageDataSource.getAll();
    this.lastMessageId = list.length > 0 ? list[list.length - 1].id : "";
  }

  /**
   * 分支组信息：返回 { current, total }，用于渲染 "< 当前 / 总数 >"
   * 转发到 BranchChainManager（ChatPage 依赖此方法，保留转发避免页面感知内部结构）
   * @param msg 当前消息
   * @returns current = 当前变体序号（1 起）；total = 分支组内变体总数
   */
  getVariantInfo(msg: Message): VariantInfo {
    return this.branchManager.getVariantInfo(msg);
  }

  /**
   * 指定对话是否正在流式回复中（连发限制按对话粒度判断，支持多对话并发）
   * @param conversationId 对话 id
   */
  private isStreamingFor(conversationId: string): boolean {
    return this.tasksOfConversation(conversationId).some((t: StreamTask) => t.isStreaming);
  }

  /**
   * 同步进行中流式任务数到后台保活服务
   * 仅统计 isStreaming=true 的任务（已暂停的任务网络请求已中止，无需保活）；
   * 任务数 > 0 且应用在后台时，保活服务会申请 dataTransfer 长时任务，
   * 防止系统冻结网络导致 SSE 连接被掐断
   */
  private syncBackgroundGuardCount(): void {
    let activeCount = 0;
    this.streamTasks.forEach((task: StreamTask) => {
      if (task.isStreaming) {
        activeCount++;
      }
    });
    BackgroundRunGuardService.getInstance().updateStreamingTaskCount(activeCount);
  }

  /**
   * 节流刷新：将任务缓冲区的增量文本合并后一次性写入 Message 属性
   * 刷新间隔见 STREAM_FLUSH_INTERVAL_MS 常量；每个 StreamTask 独立调度，多对话并发流互不影响
   * @param task 当前正在流式填充的流式任务
   */
  private scheduleFlush(task: StreamTask): void {
    /* 已有定时器在等待 → 跳过，本次增量会在下次 flush 时一并写入 */
    if (task.flushTimerId !== -1) {
      return;
    }
    task.flushTimerId = setTimeout(() => {
      /**
       * 用户滚动手势（DRAG/FLING/滚动条等）期间暂停 UI 写入：底部 item 高度不再变化，
       * 避免与 List 滚动布局竞争抖动；buffer 继续累积，滚动结束后的
       * 下一次调度 / onComplete / 暂停 会统一 flush，内容不丢
       */
      if (this.isUserScrolling) {
        task.flushTimerId = -1;
        return;
      }
      /* 合并缓冲区内容，一次性写入（触发 @Trace → MessageBubble 重绘） */
      task.flush();
      /**
       * 节流持久化：每 2.5s 把已生成内容落库一次（generation_status=partial）。
       * 进程被终止时，DB 已保存最近 2.5s 内的全部内容，重启后可恢复「继续生成」；
       * 异步 fire-and-forget，不阻塞 UI 线程（按消息粒度节流，多分支互不干扰）
       */
      const now = Date.now();
      const last = this.streamPersistTime.get(task.aiMsg.id);
      if (last === undefined || now - last >= 2500) {
        this.streamPersistTime.set(task.aiMsg.id, now);
        ConversationRepository.getInstance().updateMessage(task.aiMsg);
      }
      /* 仅当前对话正在展示该任务时才滚动，避免 A 对话的流把 B 对话列表拖到底部 */
      if (this.currentConversationId === task.conversationId) {
        /**
         * 思考阶段（多阶段思考/搜索穿插）流式增量快，动画跟不上 → 即时钉底；
         * 正文生成阶段相对慢 → 用防抖+动画保留顺滑观感
         */
        if (task.aiMsg.isThinking) {
          this.scrollToBottom();
        } else {
          this.scrollToBottomSmooth();
        }
      }
    }, STREAM_FLUSH_INTERVAL_MS); // 流式 UI 合并刷新间隔
  }

  /* 列表滚动控制（由页面 build 事件绑定） */

  /**
   * 用户操作屏幕标记（ChatPage 的 onTouch Down 置位）：
   * 生成期间用户触摸列表操作内容时，停止所有自动滚动，避免消息完成生成时打断操作
   */
  markUserOperating(operating: boolean): void {
    this.isUserOperating = operating;
  }

  /* 用户主动操作（发送/编辑/新建/切换对话/回到底部）→ 重置滚动跟随状态，恢复自动钉底 */
  resetScrollFollow(): void {
    this.isUserOperating = false;
  }

  /**
   * 滚动到达列表底部边缘（ChatPage onReachEnd 回调）：
   * 切换分支锚点静默期内忽略——补偿滚动（代码滚动）到达底部不代表用户行为，
   * 若此时清除"操作中"标记并恢复跟随，后续 Markdown 异步渲染增高会触发自动钉底跳变
   */
  handleReachEnd(): void {
    if (Date.now() < this.anchorSuppressUntil) {
      return;
    }
    this.setAtBottom(true);
    /**
     * 挂起的思考块折叠请求延后到 onScrollStop 放行（见 handleScrollStop）：
     * 若在此触底瞬间放行，折叠收缩会与"滚动刚停稳"的时刻重叠，产生突兀位移
     * 仅当"到达底部"由用户手势滚动（DRAG/FLING 等）导致时才清除"操作中"标记恢复跟随。
     * 代码滚动（自动跟随 scrollEdge）到达底部会异步触发 onReachEnd，若在此无条件 resetScrollFollow，
     * 会误清"生成中用户触摸阅读"设置的 isUserOperating，导致完成生成时重新钉底
     */
    if (this.lastScrollIsUserGesture) {
      this.resetScrollFollow();
    }
  }

  /* 自动跟随开关（onWillScroll 取消 / onReachEnd 恢复） */
  setAtBottom(value: boolean): void {
    this.isAtBottom = value;
  }

  /**
   * 记录最近一次滚动来源（ChatPage onWillScroll 调用）：
   * 供 onReachEnd 区分"用户滚回底部"与"代码滚动到底"，避免误清操作中标记
   */
  setLastScrollSource(isUserGesture: boolean): void {
    this.lastScrollIsUserGesture = isUserGesture;
  }

  /**
   * 用户是否正在滚动手势中（DRAG/FLING/滚动条等，ChatPage onWillScroll/onTouch/onScrollStop 调用）：
   * 滚动期间暂停流式 UI 写入，避免底部 item 高度变化与滚动竞争抖动
   */
  setUserScrolling(scrolling: boolean): void {
    this.isUserScrolling = scrolling;
  }

  /**
   * 滚动完全停止（ChatPage onScrollStop 回调）：
   * 恢复流式 UI 写入；并尝试放行挂起的思考块折叠请求（放行前会在 flush 内复查"在底部且未操作"）。
   * 放行时机放在滚动停止而非触底瞬间：折叠收缩发生在用户手离开屏幕、回弹结束之后，
   * 再配合气泡侧 200ms 收起动画，位移被过渡吸收，不再与"刚停稳"的动作重叠成突兀跳动
   */
  handleScrollStop(): void {
    this.setUserScrolling(false);
    this.flushPendingAutoFold();
  }

  /**
   * 手指抬起（ChatPage onTouch Up/Cancel 回调）：
   * 结束滚动状态、清除"操作中"标记，并尝试放行挂起的思考块折叠请求。
   * onTouch Up 可能被 Markdown 文本选择等手势拦截而未触发 onScrollStop，此处兜底恢复状态
   */
  onTouchReleased(): void {
    this.setUserScrolling(false);
    this.markUserOperating(false);
    this.flushPendingAutoFold();
  }

  /**
   * 流式结束 → 请求自动折叠思考块（MessageBubble 收到 foldVersion 信号后动画收起）：
   * 统一挂起 + 延迟 500ms 再复查放行——延迟窗口给用户短暂"看到生成结束"的缓冲，
   * 窗口内用户若滑离底部/开始操作，复查不通过则保留挂起（不折叠、不跳动），
   * 等回到底部并停稳（handleScrollStop / onTouchReleased）再放行。
   * 不按"当前是否在底部"立即放行：放行与执行分离（气泡侧不再有延迟）会留下
   * "放行时在底部、500ms 后折叠时已滑离"的窗口，正是"滑到底部后再滑一下会跳"的根因
   */
  private requestAutoFold(msg: Message): void {
    this.pendingAutoFold.push(msg);
    if (this.autoFoldFlushTimerId === -1) {
      this.autoFoldFlushTimerId = setTimeout(() => {
        this.autoFoldFlushTimerId = -1;
        this.flushPendingAutoFold();
      }, 500);
    }
  }

  /**
   * 放行所有待折叠请求（此刻折叠由气泡 200ms 动画平滑收起，钉底态下不产生跳动）。
   * 前置条件：用户停在底部且手指未触摸；不满足（500ms 窗口内已滑离/触摸）→ 保留挂起，
   * 等下次触发（handleScrollStop / onTouchReleased / jumpToBottom）再复查
   */
  private flushPendingAutoFold(): void {
    if (this.pendingAutoFold.length === 0) {
      return;
    }
    if (!this.isAtBottom || this.isUserOperating) {
      return;
    }
    this.pendingAutoFold.forEach((msg: Message) => {
      msg.foldVersion++;
    });
    this.pendingAutoFold = [];
  }

  /* 是否处于"自动跟随"状态（用户未在操作屏幕、且停留在底部时才允许自动钉底） */
  private shouldAutoScroll(): boolean {
    /* 切换分支锚点静默期内不自动钉底，避免异步渲染增高/补偿滚动触发 onReachEnd 后跳到底 */
    if (Date.now() < this.anchorSuppressUntil) {
      return false;
    }
    /* 编辑态下不自动钉底：保持"气泡底部与输入区顶部对齐"的位置，不被流式输出/消息增高拉回 */
    if (this.editingMessageId.length > 0) {
      return false;
    }
    return this.isAtBottom && !this.isUserOperating;
  }

  /* 底层滚动：直达列表底部边缘，无任何守卫（scrollEdge 优先，个别版本回退 scrollToIndex） */
  private scrollToBottomEdge(): void {
    try {
      this.listScroller.scrollEdge(Edge.Bottom);
    } catch (e) {
      this.listScroller.scrollToIndex(
        this.messageDataSource.totalCount() - 1,
        false,
        ScrollAlign.END,
      );
    }
  }

  /* 滚动到最底部（确保最新消息可见） */
  scrollToBottom(): void {
    /* 不在最底部 或 用户正在操作 → 不回滚 */
    if (!this.shouldAutoScroll()) {
      return;
    }
    this.scrollToBottomEdge();
  }

  /* 悬浮按钮强制滚到底（用户主动点击，不依赖 isAtBottom 守卫；scrollToBottom 有守卫不适用） */
  jumpToBottom(): void {
    this.resetScrollFollow(); // 用户主动回到底部 → 恢复自动跟随
    this.setAtBottom(true); // 兜底：滚完直接隐藏按钮（个别版本 scrollEdge 可能不触发 onReachEnd）
    this.setUserScrolling(false); // 主动回到底部 → 结束滚动状态，恢复流式 UI 写入
    this.flushPendingAutoFold(); // 用户主动回到底部 → 放行挂起的思考块折叠请求
    this.scrollToBottomEdge();
  }

  /* 正文生成阶段的平滑跟随：50ms 防抖 + 200ms EaseOut 动画（防抖保证同一时间只有一组动画，避免动画堆积） */
  private scrollToBottomSmooth(): void {
    if (!this.shouldAutoScroll()) {
      return;
    }
    if (this.followAnimationTimerId >= 0) {
      clearTimeout(this.followAnimationTimerId);
    }
    this.followAnimationTimerId = setTimeout(() => {
      this.followAnimationTimerId = -1;
      if (!this.shouldAutoScroll()) {
        return;
      }
      if (this.scrollAnimator !== undefined) {
        this.scrollAnimator(() => this.scrollToBottom());
      } else {
        this.scrollToBottom();
      }
    }, 50);
  }

  /* 页面注入滚动动画执行器（V2 组件外无 UIContext，由 ChatPage 的 getUIContext().animateTo 提供） */
  setScrollAnimator(animator: (action: () => void) => void): void {
    this.scrollAnimator = animator;
  }

  /**
   * 搜索跳转定位：滚动到指定消息（屏幕中间）
   * 与 pinToBottomAfterLoad 相同的挂起/重试机制：懒加载 + Markdown 异步渲染导致 item 高度
   * 在渲染完成后才确定，单次 scrollToIndex 定位不稳，需间隔重试直至位置稳定。
   * 定位不依赖 shouldAutoScroll 守卫（用户可能本就不在底部），直接操作 listScroller；
   * 定位后 isAtBottom 保持 false（不在底部），item 增高不会触发钉底拉回。
   * @param idx 消息在激活链中的下标
   * @param remain 剩余重试次数（120ms × N，默认约 720ms 兜底）
   */
  private pinToMessageIndex(idx: number, remain: number = 6): void {
    if (this.isDestroyed || remain <= 0) {
      this.pendingFocusIndex = -1;
      return;
    }
    /* List 未完成首帧布局 → 挂起，等 onListFirstLayout() 触发后再执行 */
    if (!this.isListLayoutReady) {
      this.pendingFocusIndex = idx;
      return;
    }
    this.pendingFocusIndex = -1;
    try {
      this.listScroller.scrollToIndex(idx, false, ScrollAlign.CENTER);
    } catch (e) {
      /* 个别版本可能抛异常，交给重试兜底 */
    }
    setTimeout(() => {
      this.pinToMessageIndex(idx, remain - 1);
    }, 120);
  }

  /**
   * 加载/重建列表后的多次钉底重试（入口 + 重试循环一体）：
   * 解决"首次打开分支多、Markdown 渲染重的对话滚不到最后一条"的问题——
   * 懒加载 + Markdown 异步渲染导致 item 高度在渲染完成后才确定，单次 scrollToIndex
   * 只能滚到当前已知高度的底部；内容持续增高后相对位置不再在底。此处每间隔固定时长
   * 重新钉底一次，直至内容高度稳定或用户开始操作（isAtBottom / isUserOperating 守卫）。
   *
   * 注意：从侧边栏返回时 List 可能尚未完成首帧布局（转场动画中），此刻 scrollToIndex
   * 不生效；若布局未就绪，请求先挂起，由 onListFirstLayout() 在布局完成时触发，
   * 避免"打开瞬间先停留在列表顶部"。
   * 重试仅作兜底：主体钉底已由 onListItemHeightChanged（item 渲染增高即时驱动）负责，
   * 故次数已缩减以降低空转。
   * @param remain 剩余重试次数（120ms × N，默认约 720ms 兜底）
   */
  private pinToBottomAfterLoad(remain: number = 6): void {
    if (this.isDestroyed || remain <= 0) {
      return;
    }
    /* List 未完成首帧布局 → 挂起，等 onListFirstLayout() 触发后再执行 */
    if (!this.isListLayoutReady) {
      this.pendingPinToBottom = true;
      return;
    }
    /* 用户已手动滚动或离开底部 → 停止自动钉底 */
    if (!this.shouldAutoScroll()) {
      return;
    }
    this.scrollToBottom();
    setTimeout(() => {
      this.pinToBottomAfterLoad(remain - 1);
    }, 120);
  }

  /**
   * List 首帧布局完成回调（ChatPage 的 List.onAreaChange 首次触发）：
   * 布局就绪后立即开始钉底，消除"打开瞬间停留在列表顶部"的现象
   */
  onListFirstLayout(): void {
    if (this.isListLayoutReady) {
      return;
    }
    this.isListLayoutReady = true;
    /* 此前有挂起的搜索定位请求（定位发生在布局就绪前）→ 优先执行定位 */
    if (this.pendingFocusIndex >= 0) {
      const idx = this.pendingFocusIndex;
      this.pendingFocusIndex = -1;
      this.pinToMessageIndex(idx);
      return;
    }
    /* 此前有挂起的钉底请求（加载对话发生在布局就绪前）→ 立即执行 */
    if (this.pendingPinToBottom) {
      this.pendingPinToBottom = false;
      this.pinToBottomAfterLoad();
    }
  }

  /**
   * 消息项高度变化回调（ChatPage 的 ListItem.onAreaChange）：
   * Markdown 异步渲染完成后 item 增高 → 若当前处于钉底状态，立即重新滚动到底，
   * 比固定间隔重试响应更快且无空转。
   *
   * 流式期间（思考/正文）统一跳过：跟随交给 scheduleFlush 的单一滚动路径（思考→即时、
   * 正文→动画）。否则思考阶段 reasoning 快速增长会在 onAreaChange（布局回调）内高频
   * 调用 scrollEdge，与布局/滚动互相触发，用户在思考阶段手动滑动时出现明显抖动。
   * @param delta 高度增量（vp），负值（折叠/移除）忽略
   */
  onListItemHeightChanged(delta: number): void {
    if (delta <= 0) {
      return;
    }
    /* 锚点恢复/静默期内：新变体渲染增高不触发自动钉底，避免打断操作栏位置恢复 */
    if (this.isRestoringAnchor || Date.now() < this.anchorSuppressUntil) {
      return;
    }
    if (!this.shouldAutoScroll()) {
      return;
    }
    /* 流式期间跟随统一由 scheduleFlush 驱动，跳过避免双路滚动竞争 */
    if (this.isTailStreaming()) {
      return;
    }
    this.scrollToBottom();
  }

  /* 当前激活链尾是否正在流式回复中（流式期间 onListItemHeightChanged 跳过，交给 scheduleFlush） */
  private isTailStreaming(): boolean {
    const task = this.tailTask();
    return task !== undefined && task.isStreaming;
  }

  /**
   * 判断当前消息是否需要显示时间分割线
   * 规则：
   *   1.第一条消息必显示
   *   2.与上一条消息间隔 > 10 分钟才显示
   * @param index 当前消息在数组中的索引
   */
  shouldShowTimeDivider(index: number): boolean {
    /* 第一条消息必显示时间 */
    if (index === 0) {
      return true;
    }
    const current = this.messageDataSource.getData(index);
    const previous = this.messageDataSource.getData(index - 1);
    return current.createdAt - previous.createdAt > 10 * 60 * 1000; // 时间间隔 > 10 分钟（毫秒）
  }

  /* 判断侧边栏是否标记"当前对话"高亮 */
  getCurrentConversationId(): string {
    return this.currentConversationId;
  }
}
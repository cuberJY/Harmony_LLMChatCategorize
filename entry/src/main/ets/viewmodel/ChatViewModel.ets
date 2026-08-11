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
import { Message } from "../model/Message";
import { StreamCallbacks } from "../service/provider/LLMProvider";
import { StreamTask } from "../service/StreamTask";
import { LLMProviderFactory } from "../service/LLMProviderFactory";
import { AppConfig } from "../config/AppConfig";
import { showToast } from "../common/Utils";
import { BackgroundRunGuardService } from "../service/BackgroundRunGuardService";

/**
 * 分支组变体信息（用于气泡左下角渲染 "< 当前 / 总数 >"）
 * @param current 当前变体序号（1 起）
 * @param total 分支组内变体总数
 */
export interface VariantInfo {
  current: number;
  total: number;
}

/**
 * 消息列表数据源（配合 LazyForEach 使用）
 * 实现 IDataSource 接口，只渲染可视区域内的消息，减少渲染开销
 */
export class MessageDataSource implements IDataSource {
  private messages: Message[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.messages.length;
  }

  getData(index: number): Message {
    return this.messages[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos = this.listeners.indexOf(listener);
    if (pos >= 0) {
      this.listeners.splice(pos, 1);
    }
  }

  // 添加一条消息并通知 LazyForEach 创建对应 ListItem
  push(msg: Message): void {
    this.messages.push(msg);
    this.listeners.forEach((l: DataChangeListener) => l.onDataAdd(this.messages.length - 1));
  }

  // 整体替换消息列表（分支切换/激活链重建后调用，触发 LazyForEach 全量重载）
  replaceAll(list: Message[]): void {
    this.messages = list;
    this.listeners.forEach((l: DataChangeListener) => l.onDataReloaded());
  }

  // 获取内部数组引用（用于构造上下文等只读场景）
  getAll(): Message[] {
    return this.messages;
  }

  // 清空所有消息
  clear(): void {
    this.messages = [];
    this.listeners.forEach((l: DataChangeListener) => l.onDataReloaded());
  }
}

@ObservedV2
export class ChatViewModel {
  // UI 可观察状态（@Trace：页面 build 中读取，变化时自动刷新）

  // 是否自动跟随滚动到底部
  @Trace isAtBottom: boolean = true;
  // 顶部标题（显示当前对话标题）
  @Trace title: string = "新对话";
  // 当前模型名称
  @Trace modelName: string = "";
  // 编辑态：正在编辑的用户消息 id（空串 = 非编辑态），UI 据此显示编辑提示
  @Trace editingMessageId: string = "";
  // 编辑态：回填到底部输入框的原始内容
  @Trace editingPrefill: string = "";
  /** 
   * 底部输入区开关状态（唯一真源：发送 / 重新生成 / 新建分支共用）
   * ChatInput 切换时通过 updateSearchOptions 实时同步，
   * 保证「重新生成/新建分支」使用当前开关，而非上次发送时的值
   */
  @Trace webSearch: boolean = true;
  @Trace deepThinking: boolean = true;
  /**
   * 当前对话的流式生成状态（唯一真源，驱动 ChatInput 的发送/暂停键与「继续生成」按钮）
   * - idle：无进行中的任务 → 显示发送键
   * - streaming：生成中 → 发送键变为暂停键（点击暂停）
   * - paused：已暂停（用户点暂停键或网络异常中断）→ 显示「继续生成」按钮
   */
  @Trace streamState: "idle" | "streaming" | "paused" = "idle";

  // 供页面 build 绑定的对象

  // 消息列表滚动条
  listScroller: Scroller = new Scroller();
  // LazyForEach 消息数据源
  messageDataSource: MessageDataSource = new MessageDataSource();

  // 非状态成员（内部逻辑用）
  private dbInitPromise: Promise<void> = Promise.resolve(); // 数据库初始化完成信号
  private currentConversation: Conversation = new Conversation(); // 当前对话对象
  private currentConversationId: string = ""; // 当前对话id
  private isFirstUserMsg: boolean = true; // 标记是否第一条用户消息（决定是否生成标题）
  private isUserScrolling: boolean = false; // 是否正在手动滚动
  private isListLayoutReady: boolean = false; // List 是否已完成首帧布局（onAreaChange 首次回调置位）
  private pendingPinToBottom: boolean = false; // 布局就绪前挂起的钉底请求
  private followAnimationTimerId: number = -1; // 流式跟随动画的防抖定时器（-1 表示无挂起）
  private scrollAnimator?: (action: () => void) => void; // 页面注入的滚动动画执行器（getUIContext().animateTo）
  private isDestroyed: boolean = false; // 页面销毁标记（销毁后流回调跳过 UI 更新）
  // 当前对话的全部消息缓存（含非激活分支变体），分支切换/变体统计/激活链重建均基于它
  private allMessages: Message[] = [];
  // 进行中的流式任务表：key = 对话 id，一个对话最多一个进行中的流
  // 支持多对话并行流式：切走后原对话的流仍在后台推进，切回时由 loadConversation 重新挂载
  private streamTasks: Map<string, StreamTask> = new Map();

  // 生命周期（由页面生命周期回调转发）

  // 页面 aboutToAppear：初始化数据库（页面级 UIAbilityContext）
  aboutToAppear(context: common.UIAbilityContext): void {
    if (!context) return;
    // 保存 init promise：发送首条消息前 await，避免数据库未就绪时消息丢失
    this.dbInitPromise = DatabaseHelper.getInstance()
      .init(context)
      .then(() => {
        this.currentConversationId = this.currentConversation.id;
      });
  }

  // 页面 aboutToDisappear：标记销毁并清理所有进行中任务的定时器，防止内存泄漏
  aboutToDisappear(): void {
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
    this.syncTitleFromDb();
    this.verifyCurrentConversation();
  }

  // 当前对话已在数据库被删除（侧边栏删除后返回）→ 重置为新对话，避免残留消息
  private async verifyCurrentConversation(): Promise<void> {
    const id = this.currentConversationId;
    if (id.length === 0) return; // 空白新对话尚未入库，跳过（避免误判为"已删除"）
    const conv = await ConversationRepository.getInstance().getById(id);
    if (this.currentConversationId !== id) return; // 查询期间对话已切换，丢弃过期结果
    if (!conv) {
      this.newConversation(); // 已删除 → 清空消息列表并进入"新对话"
    }
  }

  // 对话管理

  // 新建对话：创建新对话对象、清空消息列表（不立即入库，等待首条用户消息）
  newConversation(): void {
    this.messageDataSource.clear();
    this.allMessages = [];
    this.currentConversation = new Conversation();
    this.currentConversationId = this.currentConversation.id;
    this.isFirstUserMsg = true;
    this.editingMessageId = "";
    this.editingPrefill = "";
    this.title = "新对话";
    this.streamState = "idle"; // 新对话无进行中任务，恢复发送键
  }

  /**
   * 加载指定历史对话：替换消息列表 + 更新标题
   * 并发要点：
   *   - await 后校验"仍是该对话"，丢弃过期结果（快速连续切换不会显示错乱）
   *   - 若该对话有进行中的流任务，用内存中的实时 aiMsg 替换 DB 里的空占位，恢复流式显示
   * @param conv 要加载的对话
   */
  async loadConversation(conv: Conversation): Promise<void> {
    // 1. 更新当前对话状态
    this.currentConversation = conv;
    this.currentConversationId = conv.id;
    this.isFirstUserMsg = false; // 历史对话已有消息，不再生成标题
    this.editingMessageId = "";
    this.editingPrefill = "";
    this.title = conv.title.length > 0 ? conv.title : "新聊天";

    // 2. 从数据库查询该对话的全部消息（含非激活分支变体）
    const msgs = await ConversationRepository.getInstance().getMessages(conv.id);
    // 过期结果守卫：查询期间用户又切到了其他对话 → 丢弃本次结果，避免列表显示错乱
    if (this.currentConversationId !== conv.id) {
      return;
    }
    // 保存全量缓存（分支切换/变体统计/激活链重建的唯真源）
    this.allMessages = msgs;

    // 3. 构建激活链替换列表；若有进行中的流任务，用实时 aiMsg 替换 DB 占位（避免重复）
    // 暂停任务同样处理：暂停时已把部分内容持久化，DB 会返回新实例，
    // 需用内存中的 task.aiMsg（含流式缓冲）替换链中同名占位，保证「继续生成」的增量能实时刷新到列表
    const task = this.streamTasks.get(conv.id);
    if (task !== undefined && (task.isStreaming || task.isPaused) && msgs.indexOf(task.aiMsg) < 0) {
      // 流任务消息不在 DB 中（重建期间）→ 追加到缓存，保证链上引用一致
      this.allMessages.push(task.aiMsg);
    }
    let chain = this.buildActiveChain(this.allMessages);
    if (task !== undefined && (task.isStreaming || task.isPaused)) {
      // 流任务消息已激活 → 替换链中同名占位，保证流式填充实时刷新
      chain = chain.map((m: Message) => (m.id === task.aiMsg.id ? task.aiMsg : m));
    }
    this.messageDataSource.replaceAll(chain);

    // 4. 渲染完成后滚动到底部
    this.isAtBottom = true;
    this.isUserScrolling = false;
    this.pinToBottomAfterLoad();
    // 5. 依据该对话的进行中任务刷新 UI 状态（有流任务→暂停键；暂停任务→继续生成按钮）
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
    // 查询期间对话可能已切换（如 onPop 中同步调用了 loadConversation），丢弃过期结果避免覆盖新标题
    if (!conv || this.currentConversationId !== id) return;
    this.currentConversation.title = conv.title; // 同步内存对象（后续入库/比较用）
    this.title = conv.title.length > 0 ? conv.title : "新对话"; // 同步标题栏
  }

  // 发送消息 + AI 流式回复

  /**
   * 处理用户发送：可选联网搜索 + LLM 流式回复
   *
   * 并发要点：
   *   - 捕获当前对话 id 作为任务归属，消息/占位/上下文/任务全部保持一致
   *   - 连发限制按"对话"粒度判断（isStreamingFor），不同对话的流互不影响
   *   - 每个对话一个 StreamTask，缓冲/节流/占位消息全部按任务隔离
   *   - onComplete 只更新 updated_at（避免覆盖流式期间的重命名等字段）
   *
   * 开关状态：联网搜索 / 深度思考由 this.webSearch / this.deepThinking 读取
   * （ChatInput 切换时已通过 updateSearchOptions 同步到本 VM，唯一真源）
   *
   * @param text 用户输入文本
   */
  async handleUserSend(text: string): Promise<void> {
    // 等待数据库初始化完成，确保首条消息正常入库
    await this.dbInitPromise;
    if (this.isDestroyed) return; // 页面已销毁，中止本次发送

    // 捕获当前对话 id：后续统一用捕获值，保证消息/占位/上下文/任务归属一致
    const sendConvId = this.currentConversationId;
    // 连发限制按"对话"粒度判断（放在 await 之后，避免快速连点两次双双通过检查）
    if (this.isStreamingFor(sendConvId)) {
      showToast($r("app.string.streaming_busy"));
      return;
    }

    // 编辑态：该次发送在被编辑的用户消息处创建新变体分支并重新生成
    if (this.editingMessageId.length > 0) {
      const editTargetId = this.editingMessageId;
      this.exitEditMode();
      await this.editUserMessage(editTargetId, text, this.webSearch, this.deepThinking);
      return;
    }

    // 1. 创建用户消息（parent = 激活链尾，根消息为空串）
    const tail = this.messageDataSource.getData(this.messageDataSource.totalCount() - 1);
    const userMsg = this.addMessage("user", text, tail !== undefined ? tail.id : "");
    this.scrollToBottom();

    // 2. 创建 AI 占位消息（parent = 刚发送的用户消息），保留引用用于流式填充
    const aiMsg = this.addMessage("assistant", "", userMsg.id);
    aiMsg.isThinking = true;
    aiMsg.isStreaming = true; // 流式进行中标记
    aiMsg.thinkingStartTime = Date.now();

    // 3. 构造历史上下文（不含最后一条空 AI 消息），并捕获目标对话
    // 捕获当前对话：流式期间可能切换/新建对话，onComplete 只更新捕获对象，不污染其他对话
    const targetConv = this.currentConversation;
    const context: Message[] = this.messageDataSource.getAll().slice(0, -1);

    // 4. 发起流式回复（任务登记 + 可选搜索 + 回调 + 调用 LLM）
    this.startStreamReply(sendConvId, targetConv, aiMsg, context, this.webSearch, this.deepThinking, text);
  }

  /**
   * 同步底部输入区的开关状态（ChatInput 切换时由页面转发）
   * 唯一真源：发送 / 重新生成 / 新建分支 / 编辑均读取此处的当前值，
   * 避免「重新生成/新建分支」误用上一次发送时的开关
   * @param webSearch 联网搜索开关
   * @param deepThinking 深度思考开关
   */
  updateSearchOptions(webSearch: boolean, deepThinking: boolean): void {
    this.webSearch = webSearch;
    this.deepThinking = deepThinking;
  }

  /**
   * 发起一次 AI 流式回复（普通发送 / 重新生成 / 新建分支 / 编辑 共用入口）
   * @param sendConvId 归属对话 id
   * @param targetConv 发起时捕获的对话对象（onComplete 刷新 updated_at 用）
   * @param aiMsg AI 占位消息（流式填充目标；重新生成时复用旧消息对象实现覆盖）
   * @param context 历史上下文（不含 aiMsg 本身）
   * @param webSearch 是否开启联网搜索（服务端 web_search 工具）
   * @param deepThinking 是否开启深度思考
   * @param searchQuery 保留参数（历史版本为本地搜索取词；服务端搜索后不再使用）
   */
  private async startStreamReply(
    sendConvId: string,
    targetConv: Conversation,
    aiMsg: Message,
    context: Message[],
    webSearch: boolean,
    deepThinking: boolean,
    searchQuery: string,
  ): Promise<void> {
    // 0. 若该对话已有"暂停"的任务，先清理（新请求接管；暂停的 AI 消息作为普通消息留在列表中）
    const existing = this.streamTasks.get(sendConvId);
    if (existing !== undefined && existing.isPaused) {
      existing.clearTimer();
      existing.aiMsg.isPaused = false; // 任务被新请求接管，气泡上不再显示「继续生成」
      this.streamTasks.delete(sendConvId);
    }

    // 1. 登记流式任务（替代原全局 isStreaming 标志，实现按对话隔离）
    const task = new StreamTask(sendConvId, aiMsg, targetConv);
    task.webSearchEnabled = webSearch; // 记录本次是否请求联网搜索（onComplete 据此判断搜索是否发生过）
    task.deepThinkingEnabled = deepThinking; // 记录本次深度思考开关（「继续生成」时复用）
    this.streamTasks.set(sendConvId, task);
    // 同步进行中任务数到保活服务（退后台时据此决定是否申请长时任务）
    this.syncBackgroundGuardCount();
    // 当前对话正是发起方 → UI 进入"生成中"态（发送键变为暂停键）
    if (this.currentConversationId === sendConvId) {
      this.streamState = "streaming";
    }

    // 2. 构造回调并调用 LLM Provider（回调统一操作 task，实现按对话隔离）
    this.startProviderStream(task, context, deepThinking, webSearch, "");
  }

  /**
   * 构造流式回调并调用 LLM Provider（普通发送 / 重新生成 / 新建分支 / 编辑 / 继续生成 共用）
   * @param task 已登记的任务对象（「继续生成」时复用原任务，保持 aiMsg / 归属一致）
   * @param context 本次请求的上下文（「继续生成」时末尾含已生成部分内容的 AI 消息）
   * @param deepThinking 深度思考开关
   * @param webSearch 联网搜索开关
   * @param baseContent 本次请求前 aiMsg 已含的正文（onComplete 用 baseContent+fullText 写回，
   *   避免"继续生成"时仅剩本次增量而覆盖掉暂停前已生成的内容）
   */
  private startProviderStream(
    task: StreamTask,
    context: Message[],
    deepThinking: boolean,
    webSearch: boolean,
    baseContent: string,
  ): void {
    const aiMsg = task.aiMsg;
    const callbacks: StreamCallbacks = {
      // 思考内容增量 → 攒到任务缓冲，节流刷新
      onReasoningChunk: (deltaReasoning: string) => {
        if (this.isDestroyed) return; // 页面已销毁：跳过 UI 更新
        task.reasoningBuffer += deltaReasoning;
        this.scheduleFlush(task);
      },
      // 正文增量 → 攒到任务缓冲，节流刷新
      onChunk: (deltaText: string) => {
        if (this.isDestroyed) return;
        aiMsg.searchFailed = false;
        if (aiMsg.isSearching) {
          aiMsg.isSearching = false; // 收到正文 = 服务端搜索已结束
        }
        // 收到正文 = 思考结束（状态立即变更，不延迟）
        if (aiMsg.isThinking) {
          aiMsg.isThinking = false;
          aiMsg.thinkingDuration = Math.round((Date.now() - aiMsg.thinkingStartTime) / 100) / 10;
        }
        task.streamBuffer += deltaText;
        this.scheduleFlush(task);
      },
      // 服务端开始执行联网搜索
      onWebSearchStart: () => {
        if (this.isDestroyed) return;
        task.searchEventSeen = true;
        aiMsg.isSearching = true;
      },
      // 服务端搜索完成（模型开始基于搜索结果回答）
      onWebSearchEnd: () => {
        if (this.isDestroyed) return;
        task.searchEventSeen = true;
        aiMsg.isSearching = false;
      },
      onComplete: (fullText: string) => {
        // 清除定时器并丢弃缓冲区（baseContent+fullText 包含完整内容）
        task.clearTimer();
        task.isStreaming = false;
        task.isPaused = false;
        aiMsg.isStreaming = false; // 流式结束
        aiMsg.isThinking = false;
        aiMsg.isPaused = false; // 生成完成，不再显示「继续生成」
        // baseContent（暂停前已生成）+ 本次请求的全文（新增增量）
        aiMsg.content = baseContent + fullText;
        // 请求了联网搜索但整个流中未出现任何搜索事件 → 标记搜索失败（提示已降级）
        if (task.webSearchEnabled && !task.searchEventSeen) {
          aiMsg.searchFailed = true;
        }
        task.abortHandler = null; // 请求已结束，句柄失效
        this.streamTasks.delete(task.conversationId); // 任务结束，从表中移除
        this.syncBackgroundGuardCount(); // 任务数变化，同步保活服务
        this.refreshStreamState(); // 任务已移除 → 当前对话（若为该对话）恢复 idle

        // 持久化：更新 AI 消息完整内容
        ConversationRepository.getInstance().updateMessage(aiMsg);
        // 刷新捕获对话的 updated_at：仅更新时间戳，
        // 避免整体 update 覆盖流式期间侧边栏的重命名/收藏等字段
        task.targetConv.updatedAt = aiMsg.createdAt;
        ConversationRepository.getInstance().updateTimestampOnly(task.targetConv.id, task.targetConv.updatedAt);
        // 页面已销毁：跳过滚动
        if (this.isDestroyed) return;
        // 仅在用户仍停留在原对话时滚动到底部，避免误滚其他对话
        if (this.currentConversationId === task.conversationId) {
          this.scrollToBottom();
        }
      },
      onError: (errorMessage: string) => {
        task.clearTimer();
        task.isStreaming = false;
        task.isPaused = false;
        aiMsg.isStreaming = false; // 异常结束同样退出流式态
        aiMsg.isThinking = false;
        aiMsg.isSearching = false;
        aiMsg.isPaused = false; // 错误收尾，不再显示「继续生成」
        task.abortHandler = null;
        this.streamTasks.delete(task.conversationId);
        this.syncBackgroundGuardCount(); // 任务数变化，同步保活服务
        this.refreshStreamState();
        // 保留已接收的流式内容，末尾追加错误提示（不再整体覆盖）
        const received = aiMsg.content;
        aiMsg.content =
          received.length > 0 ? `${received}\n\n[错误] ${errorMessage}` : `[错误] ${errorMessage}`;
        ConversationRepository.getInstance().updateMessage(aiMsg); // 错误消息也入库，方便用户从历史中复盘
        if (this.isDestroyed) return;
        if (this.currentConversationId === task.conversationId) {
          this.scrollToBottom();
        }
      },
      // 网络异常中断（连接被掐断等，未收到正常结束事件）→ 进入"暂停"态：
      // 保留已接收内容，任务留在表中，供用户点击「继续生成」从未完成处续写
      onInterrupted: () => {
        if (this.isDestroyed) return;
        task.clearTimer();
        task.isStreaming = false;
        task.isPaused = true;
        aiMsg.isStreaming = false;
        aiMsg.isSearching = false;
        aiMsg.isPaused = true; // 暂停态 → 气泡操作栏右上角显示「继续生成」
        if (aiMsg.isThinking) {
          aiMsg.isThinking = false;
          aiMsg.thinkingDuration = Math.round((Date.now() - aiMsg.thinkingStartTime) / 100) / 10;
        }
        task.abortHandler = null;
        this.syncBackgroundGuardCount(); // 不再有活跃网络请求，保活计数减一
        // 持久化已接收内容（继续生成时以此为基础）
        ConversationRepository.getInstance().updateMessage(aiMsg);
        // 仅当该对话仍在前台展示时更新 UI 状态并提示
        if (this.currentConversationId === task.conversationId) {
          this.streamState = "paused";
          this.scrollToBottom();
          showToast($r("app.string.stream_interrupted"));
        }
      },
    };

    // 调用 LLM（通过工厂获取 Provider，业务层不依赖具体供应商）
    // 返回值 = 中止句柄，暂停生成时调用（ChatViewModel.pauseStreaming）
    task.abortHandler = LLMProviderFactory.create().sendMessage(context, callbacks, deepThinking, webSearch);
  }

  /**
   * 暂停当前对话的生成（生成中点击暂停键触发）
   * - 将缓冲区 flush 到消息，保留已生成的全部内容
   * - 中止底层 HTTP 请求（abort 后 Provider 不再触发任何回调，避免残留事件）
   * - 任务保留在 streamTasks 表中（isPaused=true），供「继续生成」复用
   */
  pauseStreaming(): void {
    const convId = this.currentConversationId;
    const task = this.streamTasks.get(convId);
    if (task === undefined || !task.isStreaming || task.isPaused) return;
    // 1. 合并缓冲区到消息（保留已生成内容）并清除节流定时器
    task.flush();
    task.clearTimer();
    // 2. 中止底层 HTTP 请求
    task.abortHandler?.abort();
    task.abortHandler = null;
    // 3. 标记暂停态（任务保留在表中，供继续生成复用）
    task.isStreaming = false;
    task.isPaused = true;
    task.aiMsg.isStreaming = false;
    task.aiMsg.isSearching = false;
    task.aiMsg.isPaused = true; // 暂停态 → 气泡操作栏右上角显示「继续生成」
    if (task.aiMsg.isThinking) {
      task.aiMsg.isThinking = false;
      task.aiMsg.thinkingDuration = Math.round((Date.now() - task.aiMsg.thinkingStartTime) / 100) / 10;
    }
    this.streamState = "paused";
    this.syncBackgroundGuardCount(); // 网络请求已中止，保活计数减一
    // 4. 持久化已接收内容（继续生成时以此为基础）
    ConversationRepository.getInstance().updateMessage(task.aiMsg);
    this.scrollToBottom();
  }

  /**
   * 继续生成（点击「继续生成」按钮触发）：
   * 以「历史上下文 + 已生成的部分 AI 消息」重新发起流式请求，模型从未完成处续写。
   * 复用原 StreamTask（同一 aiMsg / 同一归属对话），思考与搜索开关沿用暂停前设置。
   */
  async resumeStreaming(): Promise<void> {
    await this.dbInitPromise;
    if (this.isDestroyed) return;
    const convId = this.currentConversationId;
    const task = this.streamTasks.get(convId);
    if (task === undefined || !task.isPaused) return;
    // 1. 重置为流式态
    task.isPaused = false;
    task.isStreaming = true;
    task.searchEventSeen = false; // 新一轮请求，重新判断搜索是否发生
    task.aiMsg.isStreaming = true;
    task.aiMsg.isSearching = false;
    task.aiMsg.searchFailed = false;
    task.aiMsg.isPaused = false; // 恢复生成，隐藏气泡上的「继续生成」
    task.aiMsg.isThinking = true;
    task.aiMsg.thinkingStartTime = Date.now();
    this.streamState = "streaming";
    this.syncBackgroundGuardCount();
    // 2. 构造上下文：aiMsg 之前的全部消息 + aiMsg 自身（含已生成的部分内容，模型从此续写）
    const context = this.buildContextBefore(task.aiMsg.id);
    context.push(task.aiMsg);
    // 3. 重新发起请求：baseContent = 暂停前已生成的内容（onComplete 写回时叠加本次增量）
    this.startProviderStream(task, context, task.deepThinkingEnabled, task.webSearchEnabled,
      task.aiMsg.content);
  }

  /** 依据当前对话的流式任务状态刷新 UI 状态（任务结束 / 对话切换等场景） */
  private refreshStreamState(): void {
    const task = this.streamTasks.get(this.currentConversationId);
    if (task === undefined) {
      this.streamState = "idle";
    } else if (task.isPaused) {
      this.streamState = "paused";
    } else {
      this.streamState = "streaming";
    }
  }

  /**
   * 添加消息到激活链列表并持久化（普通发送场景）
   * 自动设置分支链字段：parentId / branchGroupId(=parentId) / variantIndex(组内递增) / isActive
   * @param role 消息角色
   * @param content 消息正文
   * @param parentId 父消息 id（分支链锚点；根用户消息传 ""）
   */
  private addMessage(role: "user" | "assistant", content: string, parentId: string): Message {
    const msg = new Message(this.currentConversationId, role, content);
    msg.parentId = parentId;
    msg.branchGroupId = parentId; // 分支组锚点 = 父消息 id（同父消息互为变体）
    msg.variantIndex = this.nextVariantIndex(parentId); // 组内变体序号递增
    msg.isActive = true;
    this.allMessages.push(msg);
    this.messageDataSource.push(msg);
    // 持久化消息
    if (this.currentConversationId) {
      // 首条用户消息 → 对话真正开始，此时才将对话入库并生成标题
      // （延迟入库：确保空白对话不会出现在历史记录中）
      if (role === "user" && this.isFirstUserMsg) {
        this.isFirstUserMsg = false;
        this.currentConversation.title =
          content.length > 20 ? content.substring(0, 20) + "..." : content;
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
  private createAndPersist(role: "user" | "assistant", content: string, parentId: string): Message {
    const msg = new Message(this.currentConversationId, role, content);
    msg.parentId = parentId;
    msg.branchGroupId = parentId;
    msg.variantIndex = this.nextVariantIndex(parentId);
    msg.isActive = true;
    this.allMessages.push(msg);
    if (this.currentConversationId) {
      ConversationRepository.getInstance().insertMessage(msg);
    }
    return msg;
  }

  /** 计算指定分支组内的下一个变体序号（组内最大 index + 1） */
  private nextVariantIndex(branchGroupId: string): number {
    let max = -1;
    this.allMessages.forEach((m: Message) => {
      if (m.branchGroupId === branchGroupId && m.variantIndex > max) {
        max = m.variantIndex;
      }
    });
    return max + 1;
  }

  // ===== 重新生成 / 新建分支 / 编辑 / 切换分支（对话分支核心） =====

  /** AI 消息「重新生成」：直接覆盖当前回复内容重新生成（不产生新变体） */
  async regenerateMessage(aiMsg: Message): Promise<void> {
    await this.dbInitPromise;
    if (this.isDestroyed) return;
    const sendConvId = this.currentConversationId;
    if (this.isStreamingFor(sendConvId)) {
      showToast($r("app.string.streaming_busy"));
      return;
    }
    if (aiMsg.isUser()) return; // 仅 AI 消息支持重新生成
    // 覆盖前清空旧内容，进入流式态
    aiMsg.content = "";
    aiMsg.reasoning = "";
    aiMsg.searchFailed = false;
    aiMsg.isThinking = true;
    aiMsg.isStreaming = true;
    aiMsg.thinkingStartTime = Date.now();
    // 上下文 = 激活链中该消息之前的部分；搜索词 = 对应的用户提问
    const context = this.buildContextBefore(aiMsg.id);
    const prompt = this.findPromptOf(aiMsg);
    const targetConv = this.currentConversation;
    // 使用当前输入区开关状态（而非上次发送时的值）
    await this.startStreamReply(sendConvId, targetConv, aiMsg, context,
      this.webSearch, this.deepThinking, prompt);
  }

  /** AI 消息「新建分支」：保留旧回复，创建新变体并重新生成（旧分支整条熄灭，可切回） */
  async createBranch(aiMsg: Message): Promise<void> {
    await this.dbInitPromise;
    if (this.isDestroyed) return;
    const sendConvId = this.currentConversationId;
    if (this.isStreamingFor(sendConvId)) {
      showToast($r("app.string.streaming_busy"));
      return;
    }
    if (aiMsg.isUser()) return; // 仅 AI 消息支持新建分支
    // 1. 创建新变体（与旧回复同父、同分支组、序号 +1），先进入流式态
    const newVariant = this.createAndPersist("assistant", "", aiMsg.parentId);
    newVariant.isThinking = true;
    newVariant.isStreaming = true;
    newVariant.thinkingStartTime = Date.now();
    // 2. 熄灭旧分支（旧回复及其后续链），保留在数据库中供切换查看
    this.deactivateBranchFrom(aiMsg);
    // 3. 重建激活链（新变体成为链尾）
    await this.rebuildActiveChain(newVariant.id);
    // 4. 构造上下文并发起流式回复
    const context = this.buildContextBefore(newVariant.id);
    const prompt = this.findPromptOf(newVariant);
    const targetConv = this.currentConversation;
    // 使用当前输入区开关状态（而非上次发送时的值）
    await this.startStreamReply(sendConvId, targetConv, newVariant, context,
      this.webSearch, this.deepThinking, prompt);
  }

  /**
   * 编辑用户消息（隐含创建新分支）：
   * 在目标用户消息处创建新变体（保留原内容为旧分支），并重新生成 AI 回复
   */
  private async editUserMessage(
    editTargetId: string,
    newText: string,
    webSearch: boolean,
    deepThinking: boolean,
  ): Promise<void> {
    const sendConvId = this.currentConversationId;
    const target = this.allMessages.find(m => m.id === editTargetId);
    if (target === undefined || !target.isUser()) return; // 目标必须是用户消息
    if (this.isStreamingFor(sendConvId)) {
      showToast($r("app.string.streaming_busy"));
      return;
    }
    // 1. 创建新用户消息变体（同父、同分支组、序号 +1）
    const newUserMsg = this.createAndPersist("user", newText, target.parentId);
    // 2. 熄灭旧用户消息及其后续链
    this.deactivateBranchFrom(target);
    // 3. 重建激活链（新用户消息成为链尾）
    await this.rebuildActiveChain(newUserMsg.id);
    // 4. 创建 AI 占位（parent = 新用户消息）并入列
    const aiMsg = this.createAndPersist("assistant", "", newUserMsg.id);
    aiMsg.isThinking = true;
    aiMsg.isStreaming = true;
    aiMsg.thinkingStartTime = Date.now();
    this.reloadActiveList();
    // 5. 构造上下文并发起流式回复
    const context = this.buildContextBefore(aiMsg.id);
    const targetConv = this.currentConversation;
    await this.startStreamReply(sendConvId, targetConv, aiMsg, context, webSearch, deepThinking, newText);
  }

  /** 用户消息「编辑」：进入编辑态（内容回填输入框），发送时创建新分支 */
  startEdit(msg: Message): void {
    if (msg.isStreaming) return; // 流式中不可编辑
    this.editingMessageId = msg.id;
    this.editingPrefill = msg.content;
  }

  /** 退出编辑态（编辑发送完成 / 切换对话时调用） */
  exitEditMode(): void {
    this.editingMessageId = "";
    this.editingPrefill = "";
  }

  /** 切换分支：在当前消息的分支组内按 delta(±1) 切换变体，并整条链重建 */
  switchBranch(msg: Message, delta: number): void {
    if (msg.isStreaming) return; // 流式中不可切换
    const group = this.allMessages.filter(m => m.branchGroupId === msg.branchGroupId);
    if (group.length <= 1) return; // 只有一个变体，无需切换
    group.sort((a, b) => a.variantIndex - b.variantIndex);
    const curPos = group.findIndex(m => m.id === msg.id);
    const total = group.length;
    // 循环切换：支持跨 0 → total-1 与 total-1 → 0
    const target = group[(((curPos + delta) % total) + total) % total];
    this.rebuildActiveChain(target.id);
  }

  /**
   * 删除消息及其后续所有分支（子树整体删除）
   * - 从 DB 批量删除（消息 id 集合）
   * - 从内存缓存 allMessages 移除
   * - 若该消息正在流式输出，先中止对应流任务
   * - 列表重建；全部删空则重置为新对话（同步删除已无内容的对话记录）
   */
  async deleteMessage(msg: Message): Promise<void> {
    await this.dbInitPromise;
    if (this.isDestroyed) return;
    const convId = this.currentConversationId;
    if (convId.length === 0) return; // 空白新对话尚未入库，无可删除

    // 1. 若被删消息正是当前流式任务正在填充的消息，先中止任务
    const task = this.streamTasks.get(convId);
    if (task !== undefined && task.aiMsg.id === msg.id) {
      task.clearTimer();
      task.isStreaming = false;
      task.isPaused = false;
      msg.isStreaming = false;
      msg.isPaused = false;
      task.abortHandler?.abort(); // 中止底层 HTTP 请求（若仍在生成中）
      task.abortHandler = null;
      this.streamTasks.delete(convId);
      this.syncBackgroundGuardCount();
      this.refreshStreamState();
    }

    // 2. 收集子树 id 集合：该消息 + 所有后代（含各变体分支），沿 parentId 广度遍历
    const deleteIds: string[] = [];
    const stack: string[] = [msg.id];
    while (stack.length > 0) {
      const curId = stack.pop();
      if (curId === undefined) continue;
      if (deleteIds.indexOf(curId) >= 0) continue; // 防重复
      deleteIds.push(curId);
      this.allMessages.forEach((m: Message) => {
        if (m.parentId === curId) {
          stack.push(m.id);
        }
      });
    }

    // 3. 持久化：删除消息（子树）；若全部删空，同时删除已无内容的对话记录
    ConversationRepository.getInstance().deleteMessages(deleteIds);
    if (deleteIds.length === this.allMessages.length) {
      ConversationRepository.getInstance().deleteConversations([convId]);
    }

    // 4. 更新内存缓存并重建列表
    this.allMessages = this.allMessages.filter((m: Message) => deleteIds.indexOf(m.id) < 0);
    if (this.allMessages.length === 0) {
      this.newConversation(); // 删空 → 回到新对话状态
    } else {
      this.reloadActiveList();
    }
  }

  /**
   * 重建激活链（切换分支核心）：
   * 1. 全量熄灭 → 2. 点亮目标变体的祖先路径 → 3. 点亮目标变体的后续链
   * 4. 持久化激活状态 → 5. 重载列表
   */
  private async rebuildActiveChain(targetId: string): Promise<void> {
    const convId = this.currentConversationId;
    // 1. 全部熄灭（内存 + DB 批量）
    this.allMessages.forEach((m: Message) => {
      m.isActive = false;
    });
    ConversationRepository.getInstance().setAllMessagesInactive(convId);

    // 2. 祖先路径：目标变体 → parent → … → 根
    // 注意：ArkTS 不支持 while 条件对循环体内被重新赋值的变量做类型收窄，
    // 故统一用 string 游标 + 循环内 const 捕获 + 显式判空，保证编译通过
    const byId = new Map<string, Message>();
    this.allMessages.forEach(m => byId.set(m.id, m));
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

    // 3. 后续链：沿激活子节点延伸（无激活则取组内最早变体，保证旧分支可完整恢复）
    curId = targetId;
    while (true) {
      const node = byId.get(curId);
      if (node === undefined) break;
      const children = this.allMessages.filter(m => m.parentId === node.id);
      if (children.length === 0) break;
      const next = this.selectNextChild(children);
      if (next === undefined) break;
      next.isActive = true;
      activeIds.push(next.id);
      curId = next.id;
    }

    // 4. 持久化激活状态（逐个 UPDATE，激活链消息量有限，性能可接受）
    activeIds.forEach(id => {
      ConversationRepository.getInstance().updateMessageActive(id, true);
    });

    // 5. 重载激活链列表
    this.reloadActiveList();
  }

  /** 将节点及其激活后续链全部置为非激活（创建新分支时熄灭旧分支），同步持久化 */
  private deactivateBranchFrom(node: Message): void {
    const stack: Message[] = [node];
    while (stack.length > 0) {
      const cur = stack.pop();
      if (cur === undefined) continue; // 栈已空（防御）
      if (!cur.isActive) continue; // 已被熄灭，跳过
      cur.isActive = false;
      ConversationRepository.getInstance().updateMessageActive(cur.id, false);
      // 继续熄灭其激活子节点（分支链保证每个父节点至多一个激活子节点）
      this.allMessages.forEach((m: Message) => {
        if (m.parentId === cur.id && m.isActive) {
          stack.push(m);
        }
      });
    }
  }

  /**
   * 构建激活链：从根消息（parentId=""）出发，沿激活子节点延伸
   * 兼容旧数据（全部消息 parentId 为空）→ 按时间正序返回
   */
  private buildActiveChain(all: Message[]): Message[] {
    if (all.length === 0) return [];
    const hasParent = all.some(m => m.parentId.length > 0);
    if (!hasParent) {
      return all.slice().sort((a, b) => a.createdAt - b.createdAt);
    }
    // 根 = parentId 为空的消息（多个根取激活的，否则取最早的）
    const roots = all.filter(m => m.parentId.length === 0)
      .sort((a, b) => a.createdAt - b.createdAt);
    if (roots.length === 0) {
      return all.slice().sort((a, b) => a.createdAt - b.createdAt);
    }
    const root = roots.find(r => r.isActive) ?? roots[0];
    const chain: Message[] = [];
    const visited = new Set<string>();
    // string 游标遍历（避免 while 条件对可选变量收窄失效的 ArkTS 编译限制）
    let curId: string = root.id;
    while (true) {
      if (visited.has(curId)) break; // 防环兜底
      const node = all.find(m => m.id === curId);
      if (node === undefined) break;
      visited.add(curId);
      chain.push(node);
      const children = all.filter(m => m.parentId === node.id);
      if (children.length === 0) break;
      const next = this.selectNextChild(children);
      if (next === undefined) break;
      curId = next.id;
    }
    return chain;
  }

  /**
   * 从一组子节点（同父的变体兄弟）中选择激活链延续：
   * 优先选 isActive 节点；全部非激活时取组内最早变体（variantIndex 最小 = 原始分支）
   */
  private selectNextChild(children: Message[]): Message | undefined {
    const active = children.filter(c => c.isActive);
    if (active.length > 0) return active[0];
    const sorted = children.slice().sort((a, b) => a.variantIndex - b.variantIndex);
    return sorted.length > 0 ? sorted[0] : undefined;
  }

  /** 构造某消息之前的激活上下文（不含该消息本身），用于重新生成/新建分支 */
  private buildContextBefore(targetId: string): Message[] {
    const list = this.messageDataSource.getAll();
    const idx = list.findIndex(m => m.id === targetId);
    if (idx < 0) return list;
    return list.slice(0, idx);
  }

  /** 找到 AI 消息对应的用户提问（其父用户消息的内容），用作联网搜索关键词 */
  private findPromptOf(aiMsg: Message): string {
    const parent = this.allMessages.find(m => m.id === aiMsg.parentId);
    return parent !== undefined ? parent.content : "";
  }

  /** 依据 allMessages 的 isActive 状态重建列表（激活链）并钉到底部 */
  private reloadActiveList(): void {
    const chain = this.buildActiveChain(this.allMessages);
    this.messageDataSource.replaceAll(chain);
    this.scrollToBottom();
  }

  /**
   * 分支组信息：返回 { current, total }，用于渲染 "< 当前 / 总数 >"
   * @param msg 当前消息
   * @returns current = 当前变体序号（1 起）；total = 分支组内变体总数
   */
  getVariantInfo(msg: Message): VariantInfo {
    const group = this.allMessages.filter(m => m.branchGroupId === msg.branchGroupId);
    if (group.length === 0) {
      return { current: msg.variantIndex + 1, total: msg.variantIndex + 1 };
    }
    // 按变体序号排序，用"组内位置"计算当前序号
    // 原因：删除某条变体后 variantIndex 会留下空洞（如 0,1,2 删除 1 后剩 0,2），
    // 若直接用 variantIndex+1 计算 current，会出现 current > total（如显示 3/2）
    const sorted = group.slice().sort((a, b) => a.variantIndex - b.variantIndex);
    const pos = sorted.findIndex(m => m.id === msg.id);
    // 组内去重统计变体数（variantIndex 唯一）
    const indexes = new Set<number>();
    group.forEach(m => indexes.add(m.variantIndex));
    return { current: Math.max(1, pos + 1), total: Math.max(1, indexes.size) };
  }

  /**
   * 指定对话是否正在流式回复中（连发限制按对话粒度判断，支持多对话并发）
   * @param conversationId 对话 id
   */
  private isStreamingFor(conversationId: string): boolean {
    const task = this.streamTasks.get(conversationId);
    return task !== undefined && task.isStreaming;
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
   * 每 50ms 最多刷新一次，将 ~100 次/秒的 UI 更新降到 ~20 次/秒
   * 每个 StreamTask 独立调度，多个对话并发流互不影响
   * @param task 当前正在流式填充的流式任务
   */
  private scheduleFlush(task: StreamTask): void {
    // 已有定时器在等待 → 跳过，本次增量会在下次 flush 时一并写入
    if (task.flushTimerId !== -1) {
      return;
    }
    task.flushTimerId = setTimeout(() => {
      // 合并缓冲区内容，一次性写入（触发 @Trace → MessageBubble 重绘）
      task.flush();
      // 仅当前对话正在展示该任务时才滚动，避免 A 对话的流把 B 对话列表拖到底部
      if (this.currentConversationId === task.conversationId) {
        this.scrollToBottomSmooth(); // 平滑跟随（200ms 动画），消除流式瞬移感
      }
    }, 50); // 50ms ≈ 20fps，肉眼几乎无感知
  }

  // 列表滚动控制（由页面 build 事件绑定）

  // 用户开始/停止滚动（onTouch / onScrollStop）
  setUserScrolling(scrolling: boolean): void {
    this.isUserScrolling = scrolling;
  }

  // 自动跟随开关（onWillScroll 取消 / onReachEnd 恢复）
  setAtBottom(value: boolean): void {
    this.isAtBottom = value;
  }

  // 滚动到最底部（确保最新消息可见）
  scrollToBottom(): void {
    // 不在最底部 或 用户正在操作 → 不回滚
    if (!this.isAtBottom || this.isUserScrolling) {
      return;
    }
    // 优先 scrollEdge 直达底部边缘：不依赖末尾 item 是否已懒加载渲染，比 scrollToIndex 更可靠；
    // 个别平台版本不支持时回退到 scrollToIndex(末尾, END)
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

  // 流式跟随的平滑滚动：50ms 防抖 + 200ms EaseOut 动画（防抖保证同时间只有一组动画，避免动画堆积抖动）
  private scrollToBottomSmooth(): void {
    if (!this.isAtBottom || this.isUserScrolling) {
      return;
    }
    if (this.followAnimationTimerId >= 0) {
      clearTimeout(this.followAnimationTimerId);
    }
    this.followAnimationTimerId = setTimeout(() => {
      this.followAnimationTimerId = -1;
      if (!this.isAtBottom || this.isUserScrolling) {
        return;
      }
      if (this.scrollAnimator !== undefined) {
        // 由页面注入的 animateTo 提供 200ms EaseOut 过渡，消除流式跟随的瞬移感
        this.scrollAnimator(() => this.scrollToBottom());
      } else {
        this.scrollToBottom();
      }
    }, 50);
  }

  // 页面注入滚动动画执行器（V2 组件外无 UIContext，由 ChatPage 的 getUIContext().animateTo 提供）
  setScrollAnimator(animator: (action: () => void) => void): void {
    this.scrollAnimator = animator;
  }

  /**
   * 加载/重建列表后的多次钉底重试（入口 + 重试循环一体）：
   * 解决"首次打开分支多、Markdown 渲染重的对话滚不到最后一条"的问题——
   * 懒加载 + Markdown 异步渲染导致 item 高度在渲染完成后才确定，单次 scrollToIndex
   * 只能滚到当前已知高度的底部；内容持续增高后相对位置不再在底。此处每间隔固定时长
   * 重新钉底一次，直至内容高度稳定或用户开始操作（isAtBottom / isUserScrolling 守卫）。
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
    // List 尚未完成首帧布局 → 挂起，等 onListFirstLayout() 触发后再执行
    if (!this.isListLayoutReady) {
      this.pendingPinToBottom = true;
      return;
    }
    // 用户已开始手动滚动或离开底部 → 停止自动钉底，避免干扰阅读
    if (!this.isAtBottom || this.isUserScrolling) {
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
    // 若此前已有挂起的钉底请求（加载对话发生在布局就绪前）→ 立即执行
    if (this.pendingPinToBottom) {
      this.pendingPinToBottom = false;
      this.pinToBottomAfterLoad();
    }
  }

  /**
   * 消息项高度变化回调（ChatPage 的 ListItem.onAreaChange）：
   * Markdown 异步渲染完成后 item 增高 → 若当前处于钉底状态，立即重新滚动到底，
   * 比固定间隔重试响应更快且无空转。流式期间由 scrollToBottomSmooth 统一负责平滑跟随，
   * 这里跳过以避免无动画滚动打断动画。
   * @param delta 高度增量（vp），负值（折叠/移除）忽略
   */
  onListItemHeightChanged(delta: number): void {
    if (delta <= 0) {
      return;
    }
    if (!this.isAtBottom || this.isUserScrolling) {
      return;
    }
    if (this.isCurrentStreaming()) {
      return; // 流式跟随交给 scrollToBottomSmooth（带动画）
    }
    this.scrollToBottom();
  }

  // 当前对话是否正在流式回复中（onListItemHeightChanged 据此跳过，避免与动画跟随竞争）
  private isCurrentStreaming(): boolean {
    const task = this.streamTasks.get(this.currentConversationId);
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
    // 第一条消息：必须显示时间
    if (index === 0) {
      return true;
    }
    const current = this.messageDataSource.getData(index);
    const previous = this.messageDataSource.getData(index - 1);
    return current.createdAt - previous.createdAt > 10 * 60 * 1000; // 时间间隔 > 10 分钟（毫秒）
  }

  // 判断侧边栏是否标记"当前对话"高亮
  getCurrentConversationId(): string {
    return this.currentConversationId;
  }
}
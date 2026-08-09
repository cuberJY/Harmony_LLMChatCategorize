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
import { SearchProviderFactory } from "../service/SearchProviderFactory";
import { AppConfig } from "../config/AppConfig";
import { showToast } from "../common/Utils";

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
  private isDestroyed: boolean = false; // 页面销毁标记（销毁后流回调跳过 UI 更新）
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
    this.currentConversation = new Conversation();
    this.currentConversationId = this.currentConversation.id;
    this.isFirstUserMsg = true;
    this.title = "新对话";
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
    this.title = conv.title.length > 0 ? conv.title : "新聊天";

    // 2. 从数据库查询该对话的全部消息
    const msgs = await ConversationRepository.getInstance().getMessages(conv.id);
    // 过期结果守卫：查询期间用户又切到了其他对话 → 丢弃本次结果，避免列表显示错乱
    if (this.currentConversationId !== conv.id) {
      return;
    }

    // 3. 替换列表；若有进行中的流任务，用实时 aiMsg 替换 DB 中的空占位消息（避免重复）
    this.messageDataSource.clear();
    const task = this.streamTasks.get(conv.id);
    let attached = false; // 是否已把任务消息挂入列表
    msgs.forEach((m: Message) => {
      if (!attached && task !== undefined && task.isStreaming && m.id === task.aiMsg.id) {
        this.messageDataSource.push(task.aiMsg);
        attached = true;
      } else {
        this.messageDataSource.push(m);
      }
    });
    // 兜底：任务消息不在 DB 结果中（异常情况），直接追加
    if (!attached && task !== undefined && task.isStreaming) {
      this.messageDataSource.push(task.aiMsg);
    }

    // 4. 渲染完成后滚动到底部
    setTimeout(() => {
      this.scrollToBottom();
    }, 100);
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
   * @param text 用户输入文本
   * @param webSearch 是否开启联网搜索
   * @param deepThinking 是否开启深度思考
   */
  async handleUserSend(text: string, webSearch: boolean, deepThinking: boolean): Promise<void> {
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

    // 1. 创建用户消息
    this.addMessage("user", text);
    this.scrollToBottom();

    // 2. 创建 AI 占位消息（保留引用，用于流式填充）
    const aiMsg = this.addMessage("assistant", "");
    aiMsg.isThinking = true;
    aiMsg.thinkingStartTime = Date.now();

    // 3. 构造历史上下文（不含最后一条空 AI 消息），并捕获目标对话
    // 捕获当前对话：流式期间可能切换/新建对话，onComplete 只更新捕获对象，不污染其他对话
    const targetConv = this.currentConversation;
    const context: Message[] = this.messageDataSource.getAll().slice(0, -1);

    // 4. 登记流式任务（替代原全局 isStreaming 标志，实现按对话隔离）
    const task = new StreamTask(sendConvId, aiMsg, targetConv);
    this.streamTasks.set(sendConvId, task);

    // 5. 联网搜索（开关开启 且 渠道已配置，才显示搜索状态并真正发起）
    if (webSearch && SearchProviderFactory.create().isAvailable()) {
      // 5.1 显示"正在搜索"状态（isSearching 控制，不写入 content）
      aiMsg.isSearching = true;

      // 5.2 调用搜索服务（失败时返回空串，不阻断流程）
      // 注意：await 期间可能切换对话，之后一律使用捕获的 sendConvId，不用 this.currentConversationId
      const searchResult = await SearchProviderFactory.create().search(text);
      if (this.isDestroyed) return; // 页面已销毁，放弃后续流程

      // 5.3 结束搜索状态
      aiMsg.isSearching = false;
      if (searchResult.length > 0) {
        // 有结果：作为 system 消息插入上下文最前面（归属捕获的对话）
        const searchMsg = new Message(
          sendConvId,
          "system",
          `以下是从网络搜索到的参考资料，请基于这些信息回答用户的问题：\n\n${searchResult}`,
        );
        context.unshift(searchMsg);
      } else {
        // 无结果：标记失败，UI 显示降级提示（content 仍为空）
        aiMsg.searchFailed = true;
      }

      // 5.4 恢复"思考中"状态，重新计时
      aiMsg.isThinking = true;
      aiMsg.thinkingStartTime = Date.now();
    }

    // 6. 构造回调并调用 LLM Provider（回调统一操作 task，实现按对话隔离）
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
        // 收到正文 = 思考结束（状态立即变更，不延迟）
        if (aiMsg.isThinking) {
          aiMsg.isThinking = false;
          aiMsg.thinkingDuration = Math.round((Date.now() - aiMsg.thinkingStartTime) / 100) / 10;
        }
        task.streamBuffer += deltaText;
        this.scheduleFlush(task);
      },
      onComplete: (fullText: string) => {
        // 清除定时器并丢弃缓冲区（fullText 包含完整内容）
        task.clearTimer();
        task.isStreaming = false;
        aiMsg.isThinking = false;
        aiMsg.content = fullText;
        this.streamTasks.delete(task.conversationId); // 任务结束，从表中移除

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
        aiMsg.isThinking = false;
        this.streamTasks.delete(task.conversationId);
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
    };

    // 7. 调用 LLM（通过工厂获取 Provider，业务层不依赖具体供应商）
    LLMProviderFactory.create().sendMessage(context, callbacks, deepThinking);
  }

  /**
   * 添加消息到数据源并持久化
   * @param role 消息角色
   * @param content 消息正文
   */
  private addMessage(role: "user" | "assistant", content: string): Message {
    const msg = new Message(this.currentConversationId, role, content);
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
   * 指定对话是否正在流式回复中（连发限制按对话粒度判断，支持多对话并发）
   * @param conversationId 对话 id
   */
  private isStreamingFor(conversationId: string): boolean {
    const task = this.streamTasks.get(conversationId);
    return task !== undefined && task.isStreaming;
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
        this.scrollToBottom();
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
    // 流式高频滚动使用无动画（false），避免动画堆积导致抖动
    this.listScroller.scrollToIndex(
      this.messageDataSource.totalCount() - 1,
      false,
      ScrollAlign.END,
    );
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
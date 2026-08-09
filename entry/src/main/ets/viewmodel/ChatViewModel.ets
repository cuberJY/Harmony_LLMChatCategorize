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
  private isStreaming: boolean = false; // 是否正在流式回复中（防止连发/并发串写）
  private dbInitPromise: Promise<void> = Promise.resolve(); // 数据库初始化完成信号
  private currentConversation: Conversation = new Conversation(); // 当前对话对象
  private currentConversationId: string = ""; // 当前对话id
  private isFirstUserMsg: boolean = true; // 标记是否第一条用户消息（决定是否生成标题）
  private isUserScrolling: boolean = false; // 是否正在手动滚动
  private streamBuffer: string = ""; // 正文增量缓冲区
  private reasoningBuffer: string = ""; // 思考增量缓冲区
  private flushTimerId: number = -1; // 节流定时器 ID

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

  // 页面 aboutToDisappear：清理节流定时器，防止内存泄漏
  aboutToDisappear(): void {
    this.clearFlushTimer();
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
   * @param conv 要加载的对话
   */
  async loadConversation(conv: Conversation): Promise<void> {
    // 1. 更新当前对话状态
    this.currentConversation = conv;
    this.currentConversationId = conv.id;
    this.isFirstUserMsg = false; // 历史对话已有消息，不再生成标题
    this.title = conv.title.length > 0 ? conv.title : "新聊天";

    // 2. 从数据库查询该对话的全部消息，替换列表
    const msgs = await ConversationRepository.getInstance().getMessages(conv.id);
    this.messageDataSource.clear();
    msgs.forEach((m: Message) => this.messageDataSource.push(m));

    // 3. 渲染完成后滚动到底部
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
   * @param text 用户输入文本
   * @param webSearch 是否开启联网搜索
   * @param deepThinking 是否开启深度思考
   */
  async handleUserSend(text: string, webSearch: boolean, deepThinking: boolean): Promise<void> {
    // 流式进行中禁止连发：避免空 AI 占位污染上下文、共享缓冲被并发流串写
    if (this.isStreaming) {
      showToast($r("app.string.streaming_busy"));
      return;
    }
    // 等待数据库初始化完成，确保首条消息正常入库
    await this.dbInitPromise;
    this.isStreaming = true;
    // 1. 创建用户消息
    this.addMessage("user", text);
    this.scrollToBottom();

    // 2. 创建 AI 占位消息（保留引用，用于流式填充）
    const aiMsg = this.addMessage("assistant", "");
    aiMsg.isThinking = true;
    aiMsg.thinkingStartTime = Date.now();

    // 3. 构造历史上下文（不含最后一条空 AI 消息）
    // 捕获当前对话：防止流式回复期间切换/新建对话时，onComplete 写错 updatedAt
    const targetConv = this.currentConversation;
    const context: Message[] = this.messageDataSource.getAll().slice(0, -1);

    // 4. 联网搜索（开关开启 且 渠道已配置，才显示搜索状态并真正发起）
    if (webSearch && SearchProviderFactory.create().isAvailable()) {
      // 4.1 显示"正在搜索"状态（isSearching 控制，不写入 content）
      //     @ObservedV2 + @Trace 自动感知属性变化，无需手动触发列表刷新
      aiMsg.isSearching = true;

      // 4.2 调用搜索服务（失败时返回空串，不阻断流程）
      const searchResult = await SearchProviderFactory.create().search(text);

      // 4.3 结束搜索状态
      aiMsg.isSearching = false;
      if (searchResult.length > 0) {
        // 有结果：作为 system 消息插入上下文最前面
        const searchMsg = new Message(
          this.currentConversationId,
          "system",
          `以下是从网络搜索到的参考资料，请基于这些信息回答用户的问题：\n\n${searchResult}`,
        );
        context.unshift(searchMsg);
      } else {
        // 无结果：标记失败，UI 显示降级提示（content 仍为空）
        aiMsg.searchFailed = true;
      }

      // 4.4 恢复"思考中"状态，重新计时
      aiMsg.isThinking = true;
      aiMsg.thinkingStartTime = Date.now();
    }

    // 5. 构造回调并调用 LLM Provider
    const callbacks: StreamCallbacks = {
      // 思考内容增量 → 先攒到缓冲区，节流刷新
      onReasoningChunk: (deltaReasoning: string) => {
        this.reasoningBuffer += deltaReasoning;
        this.scheduleFlush(aiMsg);
      },
      // 正文增量 → 先攒到缓冲区，节流刷新
      onChunk: (deltaText: string) => {
        aiMsg.searchFailed = false;
        // 收到正文 = 思考结束（状态立即变更，不延迟）
        if (aiMsg.isThinking) {
          aiMsg.isThinking = false;
          aiMsg.thinkingDuration = Math.round((Date.now() - aiMsg.thinkingStartTime) / 100) / 10;
        }
        this.streamBuffer += deltaText;
        this.scheduleFlush(aiMsg);
      },
      onComplete: (fullText: string) => {
        // 清除定时器并丢弃缓冲区（fullText 包含完整内容）
        this.clearFlushTimer();
        aiMsg.isThinking = false;
        aiMsg.content = fullText;
        this.isStreaming = false;

        ConversationRepository.getInstance().updateMessage(aiMsg); // 持久化：更新 AI 消息完整内容
        targetConv.updatedAt = aiMsg.createdAt; // 持久化：刷新捕获对话的 updated_at
        ConversationRepository.getInstance().update(targetConv);
        // 仅在用户仍停留在原对话时滚动到底部，避免误滚其他对话
        if (this.currentConversation.id === targetConv.id) {
          this.scrollToBottom();
        }
      },
      onError: (errorMessage: string) => {
        this.clearFlushTimer();
        aiMsg.isThinking = false;
        this.isStreaming = false;
        // 保留已接收的流式内容，末尾追加错误提示（不再整体覆盖）
        const received = aiMsg.content;
        aiMsg.content =
          received.length > 0 ? `${received}\n\n[错误] ${errorMessage}` : `[错误] ${errorMessage}`;
        ConversationRepository.getInstance().updateMessage(aiMsg); // 错误消息也入库，方便用户从历史中复盘
        if (this.currentConversation.id === targetConv.id) {
          this.scrollToBottom();
        }
      },
    };

    // 6. 调用 LLM（通过工厂获取 Provider，业务层不依赖具体供应商）
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
   * 节流刷新：将缓冲区的增量文本合并后一次性写入 Message 属性
   * 每 50ms 最多刷新一次，将 ~100 次/秒的 UI 更新降到 ~20 次/秒
   * @param aiMsg 当前正在流式填充的 AI 消息对象
   */
  private scheduleFlush(aiMsg: Message): void {
    // 已有定时器在等待 → 跳过，本次增量会在下次 flush 时一并写入
    if (this.flushTimerId !== -1) {
      return;
    }
    this.flushTimerId = setTimeout(() => {
      // 合并缓冲区内容，一次性写入（触发 @Trace → MessageBubble 重绘）
      if (this.reasoningBuffer.length > 0) {
        aiMsg.reasoning += this.reasoningBuffer;
        this.reasoningBuffer = "";
      }
      if (this.streamBuffer.length > 0) {
        aiMsg.content += this.streamBuffer;
        this.streamBuffer = "";
      }
      this.flushTimerId = -1;
      this.scrollToBottom();
    }, 50); // 50ms ≈ 20fps，肉眼几乎无感知
  }

  // 清除节流定时器并清空缓冲区（用于 onComplete / onError / 页面销毁）
  private clearFlushTimer(): void {
    if (this.flushTimerId !== -1) {
      clearTimeout(this.flushTimerId);
      this.flushTimerId = -1;
    }
    this.streamBuffer = "";
    this.reasoningBuffer = "";
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
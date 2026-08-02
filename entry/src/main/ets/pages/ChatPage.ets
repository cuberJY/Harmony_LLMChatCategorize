// 主聊天页面
import { router } from "@kit.ArkUI";
import { common } from "@kit.AbilityKit";
import { DatabaseHelper } from "../database/DatabaseHelper";
import { Conversation } from "../model/Conversation";
import { Message } from "../model/Message";
import { MessageBubble } from "../components/MessageBubble";
import { ChatInput } from "../components/ChatInput";
import { AppConfig } from "../config/AppConfig";
import { COLORS, FONT_SIZES, SPACING } from "../common/AppConstants";
import { AIService, StreamCallbacks } from "../service/AIService";
import { SearchService } from "../service/SearchService";

/**
 * 消息列表数据源（配合 LazyForEach 使用，方案 C）
 * 实现 IDataSource 接口，只渲染可视区域内的消息，减少渲染开销
 */
class MessageDataSource implements IDataSource {
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

@Entry
@Component
struct ChatPage {
  @State isAtBottom: boolean = true;
  @State title: string = "新对话"; // 顶部标题（显示当前对话标题）
  @State modelName: string = "";

  private edgeDownX: number = 0; // 触摸按下时的 X 坐标（用于判断是否从左边缘右滑）

  private currentConversation: Conversation = new Conversation(); // 当前对话对象
  private currentConversationId: string = ""; // 当前对话id
  private isFirstUserMsg: boolean = true; // 标记是否第一条用户消息（决定是否生成标题）

  private listScroller: Scroller = new Scroller(); // 消息列表滚动条
  private isUserScrolling: boolean = false; // 是否正在手动滚动

  // LazyForEach 数据源
  private messageDataSource: MessageDataSource = new MessageDataSource();

  // 流式渲染节流
  private streamBuffer: string = ""; // 正文增量缓冲区
  private reasoningBuffer: string = ""; // 思考增量缓冲区
  private flushTimerId: number = -1; // 节流定时器 ID

  aboutToAppear(): void {
    // 初始化数据库（页面级 UIAbilityContext）
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (context) {
      DatabaseHelper.getInstance()
        .init(context)
        .then(() => {
          // 初始化成功 → 记录当前对话 id（不立即入库，等待首条用户消息）
          this.currentConversationId = this.currentConversation.id;
        });
    }
  }

  aboutToDisappear(): void {
    // 页面销毁时清理定时器，防止内存泄漏
    this.clearFlushTimer();
  }

  /**
   * 页面每次显示时触发（首次启动 + 从 SideBarPage 返回）
   * 检查 AppConfig.selectedConversation：有值则加载该历史对话
   */
  onPageShow(): void {
    this.modelName = AppConfig.getInstance().getModel();
    const selected = AppConfig.getInstance().selectedConversation;
    if (selected) {
      // 消费掉标记，避免重复加载
      AppConfig.getInstance().selectedConversation = undefined;
      this.loadConversation(selected);
    } else {
      // 无选中对话：可能从侧边栏重命名后返回 → 回读最新标题
      this.syncTitleFromDb();
    }
  }

  /**
   * 加载指定历史对话：替换消息列表 + 更新标题
   * @param conv 要加载的对话
   */
  private async loadConversation(conv: Conversation): Promise<void> {
    // 1. 更新当前对话状态
    this.currentConversation = conv;
    this.currentConversationId = conv.id;
    this.isFirstUserMsg = false; // 历史对话已有消息，不再生成标题
    this.title = conv.title.length > 0 ? conv.title : "新聊天";

    // 2. 从数据库查询该对话的全部消息，替换列表
    const msgs = await DatabaseHelper.getInstance().getMessagesByConversation(conv.id);
    this.messageDataSource.clear();
    msgs.forEach((m: Message) => this.messageDataSource.push(m));

    // 3. 渲染完成后滚动到底部
    setTimeout(() => {
      this.scrollToBottom();
    }, 100);
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        // 左侧：侧边栏入口
        Row() {
          // "三横线"图标，点击弹出侧边栏
          SymbolGlyph($r("sys.symbol.sort"))
            .fontSize(FONT_SIZES.ICON_XL)
            .fontWeight(700)
            .fontColor([Color.Black])
        }
        .width(40)
        // 固定宽度保持对称
        .justifyContent(FlexAlign.Start)
        .onClick(() => {
          router.pushUrl({ url: "pages/SideBarPage" });
        })

        // 中间：APP 标题
        Text(this.title)
          .fontSize(FONT_SIZES.TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1)
          // 占据中间剩余空间
          .textAlign(TextAlign.Center)

        // 右侧：「新建对话」按钮
        Row() {
          SymbolGlyph($r("sys.symbol.plus"))
            .fontSize(FONT_SIZES.ICON_XL)
            .fontWeight(700)
            .fontColor([Color.Black])
        }
        .width(40)
        .justifyContent(FlexAlign.End)
        .onClick(() => {
          // 创建新对话对象，清空消息列表（不立即入库，等待首条用户消息）
          this.messageDataSource.clear();
          this.currentConversation = new Conversation();
          this.currentConversationId = this.currentConversation.id;
          this.isFirstUserMsg = true;
          this.title = "新对话";
        })
      }
      .width("100%")
      .height(SPACING.TITLE_BAR_HEIGHT)
      .padding({ left: SPACING.XL, right: SPACING.XL })
      .backgroundColor(COLORS.TITLE_BAR_BG)
      // 底部分割线
      .border({
        width: { bottom: 1 },
        color: { bottom: COLORS.DIVIDER },
      })

      // 消息列表区域
      List({ scroller: this.listScroller }) {
        /**
         * LazyForEach：懒加载列表，只渲染可视区域内的消息（方案 C）
         * 相比 ForEach 全量渲染，消息量大时显著减少渲染开销
         * Message 是 @Observed 类，属性变化由 @ObjectLink 自动感知，无需手动通知数据源
         */
        LazyForEach(
          this.messageDataSource,
          (msg: Message, index: number) => {
            ListItem() {
              Column() {
                // 判断是否需要时间分割线
                if (this.shouldShowTimeDivider(index)) {
                  Text(this.formatSmartTime(msg.createdAt))
                    .fontSize(FONT_SIZES.TIME) // 11sp
                    .fontColor(COLORS.TEXT_SECONDARY) // #999999
                    .width("100%")
                    .textAlign(TextAlign.Center) // ← 居中显示
                    .padding({ top: SPACING.LG, bottom: SPACING.XS });
                }

                // 气泡本体
                MessageBubble({ message: msg })
              }.width("100%")
            }.width("100%");
          },
          (msg: Message) => msg.id, // 用 msg.id 作为唯一 key
        )
      }
      // layoutWeight(1)：占据 Column 去掉标题栏和输入框后的全部剩余空间
      .layoutWeight(1)
      .onAreaChange((oldValue: Area, newValue: Area) => {
        // 可视区变矮 = 键盘弹出窗口被压缩 → 重新钉到底部
        if (newValue.height < oldValue.height) {
          this.scrollToBottom();
        }
      })
      .onTouch((event: TouchEvent) => {
        // 手指按下列表 = 用户正在操作
        if (event.type === TouchType.Down) {
          this.isUserScrolling = true;
        }
      })
      .onScrollStop(() => {
        // 滚动完全停止（含手指松开后的惯性滑完）→ 用户操作结束
        this.isUserScrolling = false;
      })
      // 用户手指拖动或惯性滑动 → 取消自动跟随）
      .onWillScroll(
        (scrollOffset: number, scrollState: ScrollState, scrollSource: ScrollSource) => {
          // 只有用户手指拖动/惯性滑动才取消自动跟随
          if (scrollSource === ScrollSource.DRAG || scrollSource === ScrollSource.FLING) {
            this.isAtBottom = false;
          }
        },
      )
      // 真正滚到列表底部边缘 → 恢复自动跟随
      .onReachEnd(() => {
        this.isAtBottom = true;
      })
      .width("100%")
      .backgroundColor(COLORS.PAGE_BG)
      // 列表宽高反向排列（新消息在底部）→ 不需要，正常从上到下即可
      .edgeEffect(EdgeEffect.Spring) // 滑动到顶/底部有弹性效果

      // 底部输入区域
      ChatInput({
        modelName: this.modelName, // 从配置获取当前模型
        onChange: (text: string, webSearch: boolean) => {
          this.handleUserSend(text, webSearch);
        },
      })
    }
    // 记录手指按下位置（用于边缘手势判断）
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.edgeDownX = event.touches[0].x;
      }
    })
    // 从左向右滑（起始位置在屏幕左边缘 60px 内）→ 跳转历史页
    .gesture(
      PanGesture({ direction: PanDirection.Right, distance: 40 }).onActionStart(() => {
        router.pushUrl({ url: "pages/SideBarPage" });
      }),
    )
    // Column 占满整个屏幕
    .width("100%")
    .height("100%");
  }

  /**
   * 处理用户发送：可选联网搜索 + LLM 流式回复
   * @param text 用户输入文本
   * @param webSearch 是否开启联网搜索
   */
  private async handleUserSend(text: string, webSearch: boolean): Promise<void> {
    // 1. 创建用户消息
    this.addMessage("user", text);
    this.scrollToBottom();

    // 2. 创建 AI 占位消息（保留引用，用于流式填充）
    const aiMsg = this.addMessage("assistant", "");
    aiMsg.isThinking = true;
    aiMsg.thinkingStartTime = Date.now();

    // 3. 构造历史上下文（不含最后一条空 AI 消息）
    const context: Message[] = this.messageDataSource.getAll().slice(0, -1);

    // 4. 联网搜索（开关开启 且 渠道已配置，才显示搜索状态并真正发起）
    if (webSearch && SearchService.getInstance().isAvailable()) {
      // 4.1 显示"正在搜索"状态（isSearching 控制，不写入 content）
      //     @Observed + @ObjectLink 自动感知属性变化，无需手动触发列表刷新
      aiMsg.isSearching = true;

      // 4.2 调用搜索服务（失败时返回空串，不阻断流程）
      const searchResult = await SearchService.getInstance().search(text);

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

    // 5. 构造回调并调用 AIService
    const callbacks: StreamCallbacks = {
      // 思考内容增量 → 先攒到缓冲区，节流刷新（方案 A）
      onReasoningChunk: (deltaReasoning: string) => {
        this.reasoningBuffer += deltaReasoning;
        this.scheduleFlush(aiMsg);
      },
      // 正文增量 → 先攒到缓冲区，节流刷新（方案 A）
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

        DatabaseHelper.getInstance().updateMessage(aiMsg); // 持久化：更新 AI 消息完整内容
        this.currentConversation.updatedAt = aiMsg.createdAt; // 持久化：刷新对话的 updated_at
        DatabaseHelper.getInstance().updateConversation(this.currentConversation);

        this.scrollToBottom();
      },
      onError: (errorMessage: string) => {
        this.clearFlushTimer();
        aiMsg.isThinking = false;
        aiMsg.content = `[错误] ${errorMessage}`;
        DatabaseHelper.getInstance().updateMessage(aiMsg); // 错误消息也入库，方便用户从历史中复盘
        this.scrollToBottom();
      },
    };

    // 6. 调用 LLM
    AIService.getInstance().sendMessage(context, callbacks);
  }

  /**
   * 按 id 从数据库拉取当前对话的最新标题并同步到标题栏
   * （重命名发生在侧边栏，当前页对象与侧边栏对象不是同一个实例）
   */
  private async syncTitleFromDb(): Promise<void> {
    if (this.currentConversationId.length === 0) return; // 空白新对话尚未入库，跳过
    const conv = await DatabaseHelper.getInstance().getConversationById(this.currentConversationId);
    if (conv) {
      this.currentConversation.title = conv.title; // 同步内存对象（后续入库/比较用）
      this.title = conv.title.length > 0 ? conv.title : "新对话"; // 同步标题栏
    }
  }

  /**
   * 发送消息后的通用处理方法（后续抽取到 ViewModel）
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
        DatabaseHelper.getInstance().insertConversation(this.currentConversation);
      }
      DatabaseHelper.getInstance().insertMessage(msg);
    }
    return msg;
  }

  /**
   * 节流刷新：将缓冲区的增量文本合并后一次性写入 Message 属性（方案 A）
   * 每 50ms 最多刷新一次，将 ~100 次/秒的 UI 更新降到 ~20 次/秒
   * @param aiMsg 当前正在流式填充的 AI 消息对象
   */
  private scheduleFlush(aiMsg: Message): void {
    // 已有定时器在等待 → 跳过，本次增量会在下次 flush 时一并写入
    if (this.flushTimerId !== -1) {
      return;
    }
    this.flushTimerId = setTimeout(() => {
      // 合并缓冲区内容，一次性写入（触发 @ObjectLink → MessageBubble 重绘）
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

  // 清除节流定时器并清空缓冲区（用于 onComplete / onError）
  private clearFlushTimer(): void {
    if (this.flushTimerId !== -1) {
      clearTimeout(this.flushTimerId);
      this.flushTimerId = -1;
    }
    this.streamBuffer = "";
    this.reasoningBuffer = "";
  }

  // 滚动到最底部（确保最新消息可见）
  private scrollToBottom(): void {
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

  // 对话页面过渡动画
  pageTransition() {
    // 打开（Push）：ChatPage 同时向右移动，把位置让给侧边栏
    PageTransitionExit({ type: RouteType.Push, duration: 150, curve: Curve.EaseOut }).translate({
      x: "100%",
    });
    // 返回（Pop）：ChatPage 从右侧滑回原位（向左移动）
    PageTransitionEnter({ type: RouteType.Pop, duration: 150, curve: Curve.EaseOut }).translate({
      x: "100%",
    });
  }

  /**
   * 判断当前消息是否需要显示时间分割线
   * 规则：
   *   1.第一条消息必显示
   *   2.与上一条消息间隔 > 10 分钟才显示
   * @param index 当前消息在数组中的索引
   */
  private shouldShowTimeDivider(index: number): boolean {
    // 第一条消息：必须显示时间
    if (index === 0) {
      return true;
    }
    const current = this.messageDataSource.getData(index);
    const previous = this.messageDataSource.getData(index - 1);
    return current.createdAt - previous.createdAt > 10 * 60 * 1000; // 时间间隔 > 10 分钟（10 * 60 * 1000 毫秒）
  }

  /**
   * 智能时间格式化
   *   今天 → "14:30"
   *   昨天 → "昨天 14:30"
   *   本周 → "星期三 14:30"
   *   同年 → "7/9 14:30"
   *   跨年 → "2026/7/9 14:30"
   */
  private formatSmartTime(timestamp: number): string {
    const date = new Date(timestamp);
    const now = new Date();

    // HH:MM 格式
    const time = `${date.getHours().toString().padStart(2, "0")}:${date.getMinutes().toString().padStart(2, "0")}`;
    // 同一天
    if (date.toDateString() === now.toDateString()) {
      return time;
    }
    // 昨天
    const yesterday = new Date(now);
    yesterday.setDate(now.getDate() - 1);
    if (date.toDateString() === yesterday.toDateString()) {
      return `昨天 ${time}`;
    }
    // 7天内 将两个日期归零到当天 00:00:00，用日历日差比较
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    const msgDayStart = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
    const diffDays = Math.floor((todayStart - msgDayStart) / (1000 * 60 * 60 * 24));

    if (diffDays < 7 && diffDays >= 2) {
      const weekdays = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"];
      return `${weekdays[date.getDay()]} ${time}`;
    }
    // 同年
    if (date.getFullYear() === now.getFullYear()) {
      return `${date.getMonth() + 1}/${date.getDate()} ${time}`;
    }
    // 跨年
    return `${date.getFullYear()}/${date.getMonth() + 1}/${date.getDate()} ${time}`;
  }
}

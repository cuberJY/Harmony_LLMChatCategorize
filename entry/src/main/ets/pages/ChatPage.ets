// 主聊天页面
import { Message } from "../model/Message";
import { MessageBubble } from "../components/MessageBubble";
import { ChatInput } from "../components/ChatInput";
import { AppConfig } from "../config/AppConfig";
import { COLORS, FONT_SIZES, SPACING } from "../common/AppConstants";
import { AIService, StreamCallbacks } from "../service/AIService";
import { SearchService } from "../service/SearchService";

@Entry
@Component
struct ChatPage {
  @State messages: Message[] = [];
  @State isAtBottom: boolean = true;

  // *** 当前对话 ID（后续接入数据库时会用到；现在先写死）
  private currentConversationId: string = "demo_conv_001";

  private listScroller: Scroller = new Scroller(); // 消息列表滚动条
  private isUserScrolling: boolean = false; // 是否正在手动滚动

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        // 左侧：占位（后续放侧边栏入口图标）
        Row() {
          // 这里后续换成"三横线"图标，点击弹出侧边栏
          SymbolGlyph($r("sys.symbol.space_enlarge"))
            .fontSize(FONT_SIZES.ICON_XL)
            .fontWeight(700)
            .fontColor([Color.Black])
        }
        .width(40)
        // 固定宽度保持对称
        .justifyContent(FlexAlign.Start)

        // 中间：APP 标题
        Text("新聊天")
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
          // 后续：创建新对话对象，清空消息列表
          this.messages = [];
        })
      }
      .width("100%")
      .height(52)
      .padding({ left: SPACING.MD, right: SPACING.MD })
      .backgroundColor(COLORS.TITLE_BAR_BG)
      // 底部分割线
      .border({
        width: { bottom: 1 },
        color: { bottom: COLORS.DIVIDER },
      })

      // 消息列表区域
      List({ scroller: this.listScroller }) {
        /**
         * ForEach：根据数据数组循环生成 UI
         * 第1个参数：数据数组
         * 第2个参数：(item, index) => 唯一 key（用于高效 diff 更新）
         * 第3个参数：(item) => 每个元素对应的 UI
         */
        ForEach(
          this.messages,
          (msg: Message, index: number) => {
            ListItem() {
              // 每个 ListItem 嵌入一个 MessageBubble 组件
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
        modelName: AppConfig.getInstance().getModel(), // 从配置获取当前模型
        onChange: (text: string, webSearch: boolean) => {
          this.handleUserSend(text, webSearch);
        },
      })
    }
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
    const context: Message[] = this.messages.slice(0, -1);

    // 4. 联网搜索（开关开启 且 渠道已配置，才显示搜索状态并真正发起）
    if (webSearch && SearchService.getInstance().isAvailable()) {
      // 4.1 显示"正在搜索"状态（isSearching 控制，不写入 content）
      aiMsg.isSearching = true;
      this.messages = this.messages.slice(); // 触发 UI 刷新

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
      this.messages = this.messages.slice();
    }

    // 5. 构造回调并调用 AIService
    const callbacks: StreamCallbacks = {
      // 思考内容增量
      onReasoningChunk: (deltaReasoning: string) => {
        aiMsg.reasoning += deltaReasoning;
        this.scrollToBottom();
      },
      onChunk: (deltaText: string) => {
        aiMsg.searchFailed = false;
        // 收到正文 = 思考结束
        if (aiMsg.isThinking) {
          aiMsg.isThinking = false;
          aiMsg.thinkingDuration = Math.round((Date.now() - aiMsg.thinkingStartTime) / 100) / 10;
        }
        aiMsg.content += deltaText;
        this.scrollToBottom();
      },
      onComplete: (fullText: string) => {
        aiMsg.isThinking = false;
        aiMsg.content = fullText;
        this.messages = this.messages.slice();
        this.scrollToBottom();
      },
      onError: (errorMessage: string) => {
        aiMsg.isThinking = false;
        aiMsg.content = `[错误] ${errorMessage}`;
        this.messages = this.messages.slice();
        this.scrollToBottom();
      },
    };

    // 6. 调用 LLM
    AIService.getInstance().sendMessage(context, callbacks);
  }

  /**
   * 发送消息后的通用处理方法（后续抽取到 ViewModel）
   * @param role 消息角色
   * @param content 消息正文
   */
  private addMessage(role: "user" | "assistant", content: string): Message {
    const msg = new Message(this.currentConversationId, role, content);
    this.messages.push(msg);
    return msg;
  }

  // 滚动到最底部（确保最新消息可见）
  private scrollToBottom(): void {
    // 不在最底部 或 用户正在操作 → 不回滚
    if (!this.isAtBottom || this.isUserScrolling) {
      return;
    }
    this.listScroller.scrollToIndex(this.messages.length - 1, true, ScrollAlign.END);
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
    const current = this.messages[index];
    const previous = this.messages[index - 1];
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

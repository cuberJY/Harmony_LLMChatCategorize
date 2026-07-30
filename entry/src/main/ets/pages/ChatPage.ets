// 主聊天页面
import { Message } from "../model/Message";
import { MessageBubble } from "../components/MessageBubble";
import { ChatInput } from "../components/ChatInput";
import { COLORS, FONT_SIZES, SPACING } from "../common/AppConstants";
import { AIService, StreamCallbacks } from "../service/AIService";

@Entry
@Component
struct ChatPage {
  @State messages: Message[] = [];

  // *** 当前对话 ID（后续接入数据库时会用到；现在先写死）
  private currentConversationId: string = "demo_conv_001";

  // 生命周期：页面即将显示时
  aboutToAppear(): void {
    // 加载假数据，验证气泡组件渲染效果
    // this.messages = this.getMockMessages();
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        // 左侧：占位（后续放侧边栏入口图标）
        Row() {
          // 这里后续换成"三横线"图标，点击弹出侧边栏
          SymbolGlyph($r("sys.symbol.space_enlarge"))
            .fontSize(20)
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
            .fontSize(20)
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
      List() {
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
                    .padding({ top: 16, bottom: 4 });
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
      .width("100%")
      .backgroundColor(COLORS.PAGE_BG)
      // 列表宽高反向排列（新消息在底部）→ 不需要，正常从上到下即可
      .edgeEffect(EdgeEffect.Spring) // 滑动到顶/底部有弹性效果

      // 底部输入区域
      ChatInput({
        onChange: (text: string) => {
          // 1. 创建用户消息并追加到列表
          const userMsg = new Message(this.currentConversationId, "user", text);
          this.messages.push(userMsg);

          // 2. 创建一条空的 AI 消息作为占位（后续流式填充）
          const aiMsg = new Message(this.currentConversationId, "assistant", "");
          this.messages.push(aiMsg);

          // 3. 构造历史消息数组（不含最后一条 aiMsg，因为它还为空）
          const context: Message[] = this.messages.slice(0, -1);

          // 4. 调用 AIService，通过回调逐字填充 AI 回复
          const callbacks: StreamCallbacks = {
            onChunk: (deltaText: string) => {
              // 逐字拼接到 AI 消息内容中
              aiMsg.content += deltaText;
            },
            onComplete: (fullText: string) => {
              // 确保完整文本（兜底）
              aiMsg.content = fullText;
              this.messages = this.messages.slice();
            },
            onError: (errorMessage: string) => {
              // 显示错误信息代替 AI 回复
              aiMsg.content = `[错误] ${errorMessage}`;
              this.messages = this.messages.slice();
            },
          };
          AIService.getInstance().sendMessage(context, callbacks);
        },
      })
    }
    // Column 占满整个屏幕
    .width("100%")
    .height("100%");
  }

  // 生成模拟数据，用于验证 UI 渲染效果
  private getMockMessages(): Message[] {
    return [
      new Message(
        this.currentConversationId,
        "user",
        "你好，请问 HarmonyOS NEXT 和之前版本有什么主要区别？",
      ),
      new Message(
        this.currentConversationId,
        "assistant",
        "HarmonyOS NEXT（5.0）是鸿蒙的全新版本，主要有以下变化：\n\n1. **不再兼容 Android**：完全移除 AOSP 代码，仅支持鸿蒙原生应用\n2. **ArkUI 声明式框架**：全新的 UI 开发范式\n3. **ArkTS 语言**：基于 TypeScript 深度定制\n4. **性能大幅提升**：方舟编译器 + 统一渲染引擎",
      ),
      new Message(this.currentConversationId, "user", "ArkTS 和 TypeScript 有什么不同？"),
      new Message(
        this.currentConversationId,
        "assistant",
        "ArkTS 在 TypeScript 基础上做了以下关键调整：\n\n1. **严格的静态类型检查**：编译期就能发现类型错误\n2. **装饰器扩展**：如 `@State`、`@Prop`、`@Link` 用于声明式 UI 状态管理\n3. **去掉了部分动态特性**：如 `any` 类型受限、`eval()` 不可用\n4. **原生 API 集成**：直接调用鸿蒙系统能力",
      ),
    ];
  }

  /**
   * 发送消息后的通用处理方法（后续抽取到 ViewModel）
   * @param role 消息角色
   * @param content 消息正文
   */
  private addMessage(role: "user" | "assistant", content: string): void {
    const msg = new Message(this.currentConversationId, role, content);
    this.messages.push(msg);
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
